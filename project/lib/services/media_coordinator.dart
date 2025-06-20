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

/// Coordinates all media-related operations across the app.
/// This service acts as the single entry point for all media operations,
/// creating and managing all media service dependencies internally.
class MediaCoordinator extends ChangeNotifier {
  // Internal service instances - created and managed by this coordinator
  late final PhotoManagerService _photoManager;
  late final DirectoryService _directoryService;
  late final MediaMetadataService _metadataService;
  late final MediaSearchService _mediaSearchService;

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

      // Step 2: Initialize DirectoryService first (no dependencies)
      if (kDebugMode) {
        print('📁 MediaCoordinator: Initializing DirectoryService...');
      }
      await _directoryService.initialize();

      // Step 3: Initialize MediaMetadataService with DirectoryService
      if (kDebugMode) {
        print('📊 MediaCoordinator: Initializing MediaMetadataService...');
      }
      await _metadataService.initialize(_directoryService);

      // Step 4: Initialize PhotoManagerService (request permissions first)
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

      // Step 5: Initialize MediaSearchService
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
      if (!await file.exists()) {
        if (kDebugMode) {
          print(
              '❌ MediaCoordinator: Media file does not exist: $normalizedUri');
        }
        return false;
      }

      // Check if file is readable
      try {
        await file.length();
        return true;
      } catch (e) {
        if (kDebugMode) {
          print('❌ MediaCoordinator: Media file is not accessible: $e');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error validating media URI: $e');
      }
      return false;
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
  /// Delegates to the internal MediaMetadataService
  Map<String, dynamic> getMediaContextForAi() {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return _metadataService.getMediaContextForAi();
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
      List<String> albumIds, FirestoreService firestoreService) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    await _mediaSearchService.reinitializeWithAlbums(
        albumIds, firestoreService);
  }

  /// Get an asset entity by ID
  Future<AssetEntity?> getAssetById(String id) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }
    return await _mediaSearchService.getAssetById(id);
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
