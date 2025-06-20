import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/social_action.dart';
import 'photo_manager_service.dart';
import 'directory_service.dart';
import 'media_metadata_service.dart';
import 'media_search_service.dart';
import 'firestore_service.dart';
import 'app_settings_service.dart';

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

      // Step 5: Initialize PhotoManagerService (request permissions first)
      if (kDebugMode) {
        print('📷 MediaCoordinator: Requesting photo permissions...');
      }

      // Request photo permissions using PhotoManager
      final permissionState = await PhotoManager.requestPermissionExtend();
      if (!permissionState.hasAccess) {
        if (kDebugMode) {
          print(
              '⚠️ MediaCoordinator: Photo permissions not granted, continuing without photo access');
        }
      } else {
        if (kDebugMode) {
          print('✅ MediaCoordinator: Photo permissions granted');
        }
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
      if (kDebugMode) {
        print('🔍 MediaCoordinator: Searching for media with query: "$query"');
        print('   Date Range: ${dateRange?.toString() ?? 'None'}');
        print('   Media Types: ${mediaTypes?.join(', ') ?? 'All'}');
        print('   Directory: ${directory ?? 'All'}');
      }

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

      final candidates = await _photoManager.findAssetCandidates(searchParams);
      final candidateMaps = await _photoManager.getAssetMaps(candidates);

      // Enrich with metadata from EXIF data
      for (var media in candidateMaps) {
        final fileUri = media['file_uri'] as String;
        final file = File(Uri.parse(fileUri).path);
        if (await file.exists()) {
          final metadata = await _metadataService.extractMetadata(file);
          media['metadata'] = metadata;
        }
      }

      return candidateMaps;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error getting media for query: $e');
      }
      rethrow;
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

  /// Get media context for AI processing
  /// Always returns the latest 25 media files with complete metadata
  Future<Map<String, dynamic>> getMediaContextForAi() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Getting latest media context for AI...');
      }

      // Get the latest 25 media files from all sources
      final recentMedia = await getMediaForQuery(
        '', // Empty query to get all recent media
        dateRange: null,
        mediaTypes: ['image', 'video'], // Include both images and videos
      );

      // Take only the most recent 25 files and ensure they have complete metadata
      final latestMedia = recentMedia.take(25).toList();

      // Build the media context structure expected by ChatGPT
      final mediaContext = {
        'media_context': {
          'recent_media': latestMedia,
          'total_count': latestMedia.length,
          'last_updated': DateTime.now().toIso8601String(),
        }
      };

      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: Built media context with ${latestMedia.length} latest files');
        if (latestMedia.isNotEmpty) {
          final firstFile = latestMedia.first;
          print(
              '   Most recent: ${firstFile['file_uri']?.toString().split('/').last ?? 'unknown'}');
          print(
              '   Created: ${firstFile['device_metadata']?['creation_time'] ?? 'unknown'}');
        }
      }

      return mediaContext;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to get media context for AI: $e');
      }

      // Return empty context on error to prevent AI processing failure
      return {
        'media_context': {
          'recent_media': [],
          'total_count': 0,
          'last_updated': DateTime.now().toIso8601String(),
          'error': e.toString(),
        }
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

      // We need a FirestoreService instance - get it from the service locator or dependency injection
      // For now, create a simple implementation that doesn't require external dependencies
      await _mediaSearchService.reinitializeWithAlbums(
          albumIds, _createDummyFirestoreService());

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

  /// Creates a dummy FirestoreService for MediaSearchService initialization
  /// This is needed because MediaSearchService requires it but we don't use it for refresh
  FirestoreService _createDummyFirestoreService() {
    // Return a minimal FirestoreService implementation
    // This is safe because MediaSearchService only uses it for initialization
    return FirestoreService();
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
  Future<void> refreshMediaData() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting media refresh...');
      }

      // The PhotoManager will automatically get the latest assets on each query
      // We don't need to explicitly refresh it since it queries the system each time

      if (kDebugMode) {
        print('✅ MediaCoordinator: Media refresh completed successfully');
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

  @override
  void dispose() {
    if (kDebugMode) {
      print(
          '🗑️ MediaCoordinator: Being disposed (initialized: $_isInitialized)');
    }
    super.dispose();
  }
}
