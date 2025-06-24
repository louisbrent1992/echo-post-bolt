import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as path;
import '../models/social_action.dart';
import '../models/media_validation.dart';
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

  // Smart throttling variables to prevent excessive operations
  static DateTime? _lastCacheInvalidationLog;
  static DateTime? _lastQueryLog;
  static DateTime? _lastDeepCachePurge;
  static int _queryCount = 0;

  // ========== PHASE 1: CONSOLIDATED DIRECTORY SCANNING SYSTEM ==========

  // Enhanced validation cache with smart TTL management
  final Map<String, MediaValidationCacheEntry> _validationCache = {};
  final Map<String, MediaBirthprint> _birthprintCache = {};
  final Set<String> _staleUriReferences = {};

  // Unified Directory Cache System (replaces multiple scattered caches)
  final Map<String, DirectoryCache> _unifiedDirectoryCache = {};
  final Map<String, DateTime> _directoryTimestamps = {};
  final Map<String, List<String>> _directoryFileCache = {};

  // Operation locks to prevent concurrent operations and infinite loops
  bool _isCacheInvalidating = false;
  bool _isDirectoryScanning = false;
  bool _isValidatingFileSystem = false;

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
  /// OPTIMIZED: Smart caching with hybrid PhotoManager + file system validation
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
      // Smart throttling to prevent excessive operations
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

      // OPTIMIZED: Smart cache invalidation (only when needed)
      await _smartCacheInvalidation();

      final searchParams = {
        'terms': query.split(' '),
        'original_query': query, // Add original query for space-aware matching
        'date_range': dateRange != null
            ? {
                'start': dateRange.start.toIso8601String(),
                'end': dateRange.end.toIso8601String(),
              }
            : null,
        'media_type': mediaTypes?.firstOrNull,
        'directory': directory,
      };

      // Get PhotoManager results with hybrid validation
      final photoManagerResults =
          await _getValidatedPhotoManagerResults(searchParams);

      // Get custom directory results (if enabled)
      final customResults = isCustomDirectoriesEnabled
          ? await _getValidatedCustomDirectoryResults(query,
              dateRange: dateRange,
              mediaTypes: mediaTypes,
              directory: directory)
          : <Map<String, dynamic>>[];

      // Combine and deduplicate results efficiently
      final allResults = <String, Map<String, dynamic>>{};

      // Add PhotoManager results
      for (var media in photoManagerResults) {
        final fileUri = media['file_uri'] as String;
        allResults[fileUri] = media;
      }

      // Add custom directory results
      for (var media in customResults) {
        final fileUri = media['file_uri'] as String;
        allResults[fileUri] = media;
      }

      final finalResults = allResults.values.toList();

      // Efficient sorting by creation time (newest first)
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

      // Batch metadata enrichment for performance
      await _batchEnrichMetadata(finalResults);

      if (kDebugMode && shouldLogQuery) {
        print(
            '✅ MediaCoordinator: Returning ${finalResults.length} validated results');
      }

      return finalResults;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Error getting media for query: $e');
      }
      rethrow;
    }
  }

  /// OPTIMIZED: Smart cache invalidation that prevents excessive operations
  Future<void> _smartCacheInvalidation() async {
    final now = DateTime.now();

    // Prevent concurrent cache invalidations
    if (_isCacheInvalidating) return;

    // Throttle cache invalidation to every 30 seconds minimum
    if (_lastDeepCachePurge != null &&
        now.difference(_lastDeepCachePurge!).inSeconds < 30) {
      return;
    }

    _isCacheInvalidating = true;
    _lastDeepCachePurge = now;

    try {
      final shouldLog = _lastCacheInvalidationLog == null ||
          now.difference(_lastCacheInvalidationLog!).inSeconds > 60;

      if (kDebugMode && shouldLog) {
        print('🗑️ MediaCoordinator: Smart cache invalidation...');
        _lastCacheInvalidationLog = now;
      }

      // Step 1: Clear PhotoManager caches efficiently
      await PhotoManager.clearFileCache();
      await PhotoManager.releaseCache();

      // Step 2: Smart change notification reset (only if needed)
      await _smartChangeNotificationReset();

      // Step 3: Lightweight PhotoManager state refresh
      await _lightweightStateRefresh();

      if (kDebugMode && shouldLog) {
        print('✅ MediaCoordinator: Smart cache invalidation complete');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Smart cache invalidation failed: $e');
      }
    } finally {
      _isCacheInvalidating = false;
    }
  }

  /// OPTIMIZED: Lightweight change notification reset to avoid stalling
  Future<void> _smartChangeNotificationReset() async {
    try {
      await PhotoManager.stopChangeNotify();
      await Future.delayed(const Duration(milliseconds: 100)); // Reduced delay
      await PhotoManager.startChangeNotify();
    } catch (e) {
      // Silently continue - not critical
    }
  }

  /// OPTIMIZED: Lightweight PhotoManager state refresh to avoid infinite loops
  Future<void> _lightweightStateRefresh() async {
    try {
      // Single lightweight request to refresh state
      await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true),
          ),
        ),
      );
    } catch (e) {
      // Silently continue - not critical
    }
  }

  /// OPTIMIZED: Get validated PhotoManager results with hybrid file system check
  Future<List<Map<String, dynamic>>> _getValidatedPhotoManagerResults(
      Map<String, dynamic> searchParams) async {
    // Get PhotoManager candidates
    final candidates = await _photoManager.findAssetCandidates(searchParams);
    final candidateMaps = await _photoManager.getAssetMaps(candidates);

    // Filter by enabled directories
    final filteredResults =
        await _filterPhotoManagerResultsByEnabledDirectories(candidateMaps);

    // Hybrid validation: Check against file system to eliminate stale references
    return await _hybridValidateResults(filteredResults);
  }

  /// OPTIMIZED: Hybrid validation that checks PhotoManager results against file system
  Future<List<Map<String, dynamic>>> _hybridValidateResults(
      List<Map<String, dynamic>> photoManagerResults) async {
    if (_isValidatingFileSystem)
      return photoManagerResults; // Prevent concurrent validation
    _isValidatingFileSystem = true;

    try {
      final validatedResults = <Map<String, dynamic>>[];
      final staleUris = <String>[];
      final batchSize = 20; // Process in batches to avoid blocking

      for (int i = 0; i < photoManagerResults.length; i += batchSize) {
        final batch = photoManagerResults.skip(i).take(batchSize);

        for (final result in batch) {
          final fileUri = result['file_uri'] as String;
          final filePath = Uri.parse(fileUri).path;

          // Quick file existence check
          if (await File(filePath).exists()) {
            validatedResults.add(result);
          } else {
            staleUris.add(fileUri);

            // Try to find renamed file in same directory
            final recoveredResult = await _tryRecoverRenamedFile(result);
            if (recoveredResult != null) {
              validatedResults.add(recoveredResult);
            }
          }
        }

        // Yield control between batches to prevent blocking
        await Future.delayed(const Duration(microseconds: 100));
      }

      // Purge stale references asynchronously
      if (staleUris.isNotEmpty) {
        _purgeStaleReferencesAsync(staleUris);
      }

      return validatedResults;
    } finally {
      _isValidatingFileSystem = false;
    }
  }

  /// OPTIMIZED: Try to recover renamed files efficiently
  Future<Map<String, dynamic>?> _tryRecoverRenamedFile(
      Map<String, dynamic> originalResult) async {
    final originalUri = originalResult['file_uri'] as String;
    final originalPath = Uri.parse(originalUri).path;
    final directory = path.dirname(originalPath);
    final originalFilename = path.basename(originalPath);

    // Check directory cache first
    final cachedFiles = _directoryFileCache[directory];
    if (cachedFiles != null) {
      // Look for similar filenames in cache
      final recoveredFile = _findSimilarFilename(originalFilename, cachedFiles);
      if (recoveredFile != null) {
        final updatedResult = Map<String, dynamic>.from(originalResult);
        updatedResult['file_uri'] =
            'file://${path.join(directory, recoveredFile)}';
        return updatedResult;
      }
    }

    return null;
  }

  /// OPTIMIZED: Find similar filename for renamed file recovery
  String? _findSimilarFilename(
      String originalFilename, List<String> availableFiles) {
    final baseName = path.basenameWithoutExtension(originalFilename);
    final extension = path.extension(originalFilename);

    // Look for files with same base name but different suffixes
    for (final file in availableFiles) {
      if (file.endsWith(extension)) {
        final fileBaseName = path.basenameWithoutExtension(file);

        // Check for common rename patterns
        if (fileBaseName.startsWith(baseName) &&
            (fileBaseName.contains('_copy') ||
                fileBaseName.contains('_1') ||
                fileBaseName.contains('_2'))) {
          return file;
        }
      }
    }

    return null;
  }

  /// OPTIMIZED: Get validated custom directory results with smart caching
  Future<List<Map<String, dynamic>>> _getValidatedCustomDirectoryResults(
    String query, {
    DateTimeRange? dateRange,
    List<String>? mediaTypes,
    String? directory,
  }) async {
    // Use existing custom directory search with validation
    final results = await _searchCustomDirectories(
      query,
      dateRange: dateRange,
      mediaTypes: mediaTypes,
      directory: directory,
    );

    // Validate results against file system
    final validatedResults = <Map<String, dynamic>>[];

    for (final result in results) {
      final fileUri = result['file_uri'] as String;
      final filePath = Uri.parse(fileUri).path;

      if (await File(filePath).exists()) {
        validatedResults.add(result);
      }
    }

    return validatedResults;
  }

  /// OPTIMIZED: Batch metadata enrichment for better performance
  Future<void> _batchEnrichMetadata(List<Map<String, dynamic>> results) async {
    final batchSize = 10;

    for (int i = 0; i < results.length; i += batchSize) {
      final batch = results.skip(i).take(batchSize);

      await Future.wait(batch.map((media) async {
        final fileUri = media['file_uri'] as String;
        final file = File(Uri.parse(fileUri).path);

        if (await file.exists() && media['metadata'] == null) {
          try {
            final metadata = await _metadataService.extractMetadata(file);
            media['metadata'] = metadata;
          } catch (e) {
            // Skip metadata extraction on error
          }
        }
      }));

      // Yield control between batches
      await Future.delayed(const Duration(microseconds: 100));
    }
  }

  /// OPTIMIZED: Asynchronous stale reference purging to avoid blocking
  void _purgeStaleReferencesAsync(List<String> staleUris) {
    Future.microtask(() async {
      try {
        _staleUriReferences.addAll(staleUris);

        // Remove from validation cache
        for (final uri in staleUris) {
          _validationCache.remove(uri);
          _birthprintCache.remove(uri.hashCode.toString());
        }
      } catch (e) {
        // Silent failure for cache operations
      }
    });
  }

  /// OPTIMIZED: Smart directory scanning with timestamp-based change detection
  Future<bool> _needsDirectoryRescan(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) return false;

      final currentModTime = (await directory.stat()).modified;
      final lastKnownModTime = _directoryTimestamps[directoryPath];

      if (lastKnownModTime == null ||
          currentModTime.isAfter(lastKnownModTime)) {
        _directoryTimestamps[directoryPath] = currentModTime;
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// OPTIMIZED: Update directory file cache for efficient rename detection
  Future<void> _updateDirectoryFileCache(String directoryPath) async {
    if (_isDirectoryScanning) return; // Prevent concurrent scans
    _isDirectoryScanning = true;

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) return;

      final files = <String>[];
      await for (final entity in directory.list()) {
        if (entity is File && _isSupportedMediaFile(entity.path)) {
          files.add(path.basename(entity.path));
        }
      }

      _directoryFileCache[directoryPath] = files;
    } catch (e) {
      // Silent failure
    } finally {
      _isDirectoryScanning = false;
    }
  }

  /// Check if file is a supported media type
  bool _isSupportedMediaFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    const supportedExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif',
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.wmv',
      '.flv',
      '.webm'
    };
    return supportedExtensions.contains(extension);
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

          // Check both individual terms AND the complete original query
          final originalQuery = query.toLowerCase().trim();
          final matchesSearch = searchTerms
                  .any((term) => searchText.contains(term)) ||
              (originalQuery.isNotEmpty && searchText.contains(originalQuery));
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

  /// Refreshes all media data, optionally forcing a full directory scan
  Future<void> refreshMediaData({bool forceFullScan = false}) async {
    if (_isCacheInvalidating) {
      // Wait for ongoing invalidation to complete
      while (_isCacheInvalidating) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isCacheInvalidating = true;
    try {
      if (kDebugMode) {
        final now = DateTime.now();
        final shouldLog = _lastCacheInvalidationLog == null ||
            now.difference(_lastCacheInvalidationLog!).inMinutes > 5;
        if (shouldLog) {
          print(
              '🔄 MediaCoordinator: Starting consolidated media refresh${forceFullScan ? ' with full scan' : ''}');
          _lastCacheInvalidationLog = now;
        }
      }

      // Clear all caches
      _validationCache.clear();
      _birthprintCache.clear();

      // Reset operation flags
      _isValidatingFileSystem = false;

      // ========== PHASE 1: USE CONSOLIDATED DIRECTORY SCANNING ==========
      // Instead of calling individual service methods, use our unified scanning system
      await refreshDirectoryData(
        forceFullScan: forceFullScan,
        enableSmartCaching: !forceFullScan,
      );

      // Clear PhotoManager caches for fresh data
      await PhotoManager.clearFileCache();
      await PhotoManager.releaseCache();

      // Re-initialize MediaSearchService if needed
      if (forceFullScan) {
        await _mediaSearchService.initialize();
      }

      // Notify listeners of the refresh
      notifyListeners();

      if (kDebugMode) {
        final now = DateTime.now();
        final shouldLog = _lastCacheInvalidationLog == null ||
            now.difference(_lastCacheInvalidationLog!).inMinutes > 5;
        if (shouldLog) {
          print('✅ MediaCoordinator: Consolidated media refresh completed');
        }
      }
    } finally {
      _isCacheInvalidating = false;
    }
  }

  /// OPTIMIZED: Update all directory file caches efficiently
  Future<void> _updateAllDirectoryFileCaches() async {
    if (_isDirectoryScanning) return; // Prevent concurrent operations

    try {
      final enabledDirectories = isCustomDirectoriesEnabled
          ? _directoryService.enabledDirectories.map((d) => d.path).toList()
          : DirectoryService.getPlatformDefaults().map((d) => d.path).toList();

      // Update caches for directories that need rescanning
      for (final dirPath in enabledDirectories) {
        if (await _needsDirectoryRescan(dirPath)) {
          await _updateDirectoryFileCache(dirPath);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ MediaCoordinator: Directory cache update failed: $e');
      }
    }
  }

  /// Forces a complete rescan of all selected directories
  /// OPTIMIZED: Use smart directory scanning instead of brute force
  Future<void> forceRescanDirectories() async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting optimized directory rescan...');
      }

      // Force update of all directory timestamps to trigger rescans
      _directoryTimestamps.clear();

      // Update all directory file caches
      await _updateAllDirectoryFileCaches();

      if (kDebugMode) {
        print('✅ MediaCoordinator: Optimized directory rescan completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to rescan directories: $e');
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

  // ========== Media URI Validation and Recovery System ==========

  /// Comprehensive media URI validation with automatic recovery
  /// This method validates URIs and attempts multiple recovery strategies
  Future<MediaValidationResult> validateAndRecoverMediaURI(
    String uri, {
    MediaValidationConfig config = const MediaValidationConfig(),
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    // Check smart cache first for performance optimization
    final cacheEntry = _validationCache[uri];
    if (cacheEntry != null && cacheEntry.isValid) {
      return cacheEntry.result;
    }

    final startTime = DateTime.now();

    try {
      if (config.verboseLogging) {
        print('🔍 MediaCoordinator: Starting validation for URI: $uri');
      }

      // Step 1: Basic URI validation
      final basicValidation = await validateMediaURI(uri);
      if (basicValidation) {
        final result = MediaValidationResult(
          isValid: true,
          originalUri: uri,
          recoveredUri: uri,
          recoveryMethod: MediaRecoveryMethod.none,
        );

        // Cache successful validation
        _cacheValidationResult(uri, result);

        if (config.verboseLogging) {
          print('✅ MediaCoordinator: URI is valid, no recovery needed');
        }
        return result;
      }

      // Mark as stale reference for potential purging
      if (config.enableStalePurging) {
        _staleUriReferences.add(uri);
      }

      if (!config.enableRecovery) {
        final result = MediaValidationResult(
          isValid: false,
          originalUri: uri,
          recoveredUri: null,
          recoveryMethod: MediaRecoveryMethod.failed,
          errorMessage: 'URI validation failed and recovery is disabled',
        );

        _cacheValidationResult(uri, result);
        return result;
      }

      if (config.verboseLogging) {
        print(
            '🔍 MediaCoordinator: URI validation failed, attempting recovery: $uri');
      }

      // Step 2: Attempt recovery strategies with timeout
      final recoveryResult = await _attemptMediaRecovery(uri, config)
          .timeout(config.maxRecoveryTime, onTimeout: () {
        if (config.verboseLogging) {
          print('⏰ MediaCoordinator: Recovery timeout for URI: $uri');
        }
        return MediaValidationResult(
          isValid: false,
          originalUri: uri,
          recoveredUri: null,
          recoveryMethod: MediaRecoveryMethod.failed,
          errorMessage:
              'Recovery timeout after ${config.maxRecoveryTime.inSeconds}s',
        );
      });

      // Cache recovery result
      _cacheValidationResult(uri, recoveryResult);

      final duration = DateTime.now().difference(startTime);
      if (config.verboseLogging) {
        print(
            '⏱️ MediaCoordinator: Validation completed in ${duration.inMilliseconds}ms');
      }

      return recoveryResult;
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Error during validation and recovery: $e');
      }
      final result = MediaValidationResult(
        isValid: false,
        originalUri: uri,
        recoveredUri: null,
        recoveryMethod: MediaRecoveryMethod.failed,
        errorMessage: e.toString(),
      );

      _cacheValidationResult(uri, result);
      return result;
    }
  }

  /// Cache validation result with TTL management
  void _cacheValidationResult(String uri, MediaValidationResult result) {
    // Clean expired entries periodically
    _cleanExpiredCacheEntries();

    _validationCache[uri] = MediaValidationCacheEntry(
      result: result,
      cachedAt: DateTime.now(),
    );
  }

  /// Clean expired cache entries to prevent memory bloat
  void _cleanExpiredCacheEntries() {
    final now = DateTime.now();
    _validationCache.removeWhere(
        (key, entry) => now.difference(entry.cachedAt).inHours >= 24);

    // Also clean birthprint cache periodically
    if (_birthprintCache.length > 1000) {
      _birthprintCache.clear();
    }
  }

  /// Purge stale URI references from all caching layers
  Future<void> purgeStaleReferences({
    List<String>? specificUris,
    bool forceFullPurge = false,
  }) async {
    try {
      final urisToPurge = specificUris ?? _staleUriReferences.toList();

      if (urisToPurge.isEmpty && !forceFullPurge) return;

      // 1. Remove from validation cache
      for (final uri in urisToPurge) {
        _validationCache.remove(uri);
        _birthprintCache.remove(uri.hashCode.toString());
      }

      // 2. Clear PhotoManager caches if full purge requested
      if (forceFullPurge) {
        await PhotoManager.clearFileCache();
        await PhotoManager.releaseCache();

        // 3. Clear internal service caches
        await _metadataService.refreshCache();
        await _mediaSearchService.initialize();
      }

      // 4. Clear stale reference tracking
      if (specificUris == null) {
        _staleUriReferences.clear();
      } else {
        _staleUriReferences.removeWhere((uri) => urisToPurge.contains(uri));
      }
    } catch (e) {
      // Silent failure for cache operations
    }
  }

  /// Validates a list of media items and recovers broken ones with optimized parallel processing
  Future<MediaValidationBatchResult> validateAndRecoverMediaList(
    List<MediaItem> mediaItems, {
    MediaValidationConfig config = const MediaValidationConfig(),
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    if (config.verboseLogging) {
      print(
          '🔍 MediaCoordinator: Starting batch validation for ${mediaItems.length} items');
    }

    final results = <MediaValidationResult>[];

    // Process items in parallel for better performance, but limit concurrency
    const maxConcurrent = 3;
    for (int i = 0; i < mediaItems.length; i += maxConcurrent) {
      final batch = mediaItems.skip(i).take(maxConcurrent);
      final batchResults = await Future.wait(
        batch.map(
            (item) => validateAndRecoverMediaURI(item.fileUri, config: config)),
      );
      results.addAll(batchResults);
    }

    final batchResult = MediaValidationBatchResult(results: results);

    if (config.verboseLogging) {
      print('✅ MediaCoordinator: Batch validation completed: $batchResult');
    }

    return batchResult;
  }

  /// Attempts multiple recovery strategies for broken media URIs
  Future<MediaValidationResult> _attemptMediaRecovery(
    String brokenUri,
    MediaValidationConfig config,
  ) async {
    try {
      final originalPath = Uri.parse(brokenUri).path;
      final fileName = path.basename(originalPath);
      final fileExtension = path.extension(originalPath);

      if (config.verboseLogging) {
        print('🔄 MediaCoordinator: Attempting recovery for: $fileName');
      }

      // Strategy 1: Search by exact filename in current directories
      final exactNameResult = await _recoverByExactFilename(fileName, config);
      if (exactNameResult != null) {
        return MediaValidationResult(
          isValid: true,
          originalUri: brokenUri,
          recoveredUri: exactNameResult,
          recoveryMethod: MediaRecoveryMethod.exactFilename,
          recoveryMetadata: {
            'strategy': 'exact_filename',
            'filename': fileName
          },
        );
      }

      // Strategy 2: Search by filename pattern (handle renamed files)
      final patternResult =
          await _recoverByFilenamePattern(fileName, fileExtension, config);
      if (patternResult != null) {
        return MediaValidationResult(
          isValid: true,
          originalUri: brokenUri,
          recoveredUri: patternResult,
          recoveryMethod: MediaRecoveryMethod.filenamePattern,
          recoveryMetadata: {
            'strategy': 'filename_pattern',
            'original_filename': fileName
          },
        );
      }

      // Strategy 3: Search by metadata birthprint (if enabled)
      if (config.enableMetadataMatching) {
        final metadataResult = await _recoverByMetadata(originalPath, config);
        if (metadataResult != null) {
          return MediaValidationResult(
            isValid: true,
            originalUri: brokenUri,
            recoveredUri: metadataResult,
            recoveryMethod: MediaRecoveryMethod.metadata,
            recoveryMetadata: {'strategy': 'metadata_birthprint'},
          );
        }
      }

      // Strategy 4: Force PhotoManager cache refresh and retry (if enabled)
      if (config.enableCacheRefresh) {
        await _forceComprehensiveCacheRefresh();
        final refreshResult =
            await _recoverAfterCacheRefresh(brokenUri, config);
        if (refreshResult != null) {
          return MediaValidationResult(
            isValid: true,
            originalUri: brokenUri,
            recoveredUri: refreshResult,
            recoveryMethod: MediaRecoveryMethod.cacheRefresh,
            recoveryMetadata: {'strategy': 'cache_refresh'},
          );
        }
      }

      return MediaValidationResult(
        isValid: false,
        originalUri: brokenUri,
        recoveredUri: null,
        recoveryMethod: MediaRecoveryMethod.failed,
        errorMessage: 'All recovery strategies failed',
      );
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Recovery attempt failed: $e');
      }
      return MediaValidationResult(
        isValid: false,
        originalUri: brokenUri,
        recoveredUri: null,
        recoveryMethod: MediaRecoveryMethod.failed,
        errorMessage: 'Recovery error: $e',
      );
    }
  }

  /// Recovery Strategy 1: Search by exact filename
  Future<String?> _recoverByExactFilename(
      String fileName, MediaValidationConfig config) async {
    try {
      final searchResults = await getMediaForQuery(
        fileName.replaceAll(
            path.extension(fileName), ''), // Search without extension
        mediaTypes: ['image', 'video'],
      );

      for (final result in searchResults) {
        final resultPath = Uri.parse(result['file_uri'] as String).path;
        if (path.basename(resultPath) == fileName) {
          if (config.verboseLogging) {
            print(
                '✅ MediaCoordinator: Recovered by exact filename: ${result['file_uri']}');
          }
          return result['file_uri'] as String;
        }
      }
      return null;
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Exact filename recovery failed: $e');
      }
      return null;
    }
  }

  /// Recovery Strategy 2: Search by filename pattern (handles renamed files)
  Future<String?> _recoverByFilenamePattern(
    String originalFileName,
    String extension,
    MediaValidationConfig config,
  ) async {
    try {
      // Extract base name without extension and common suffixes
      final baseName = path
          .basenameWithoutExtension(originalFileName)
          .replaceAll(RegExp(r'_\d+$'), '') // Remove _1, _2, etc.
          .replaceAll(RegExp(r'\(\d+\)$'), '') // Remove (1), (2), etc.
          .replaceAll(RegExp(r'_copy$'), '') // Remove _copy
          .replaceAll(RegExp(r'_Copy$'), '') // Remove _Copy
          .replaceAll(RegExp(r' copy$'), '') // Remove " copy"
          .replaceAll(RegExp(r' Copy$'), ''); // Remove " Copy"

      if (baseName.length < 3) {
        // Base name too short for meaningful pattern matching
        return null;
      }

      final searchResults = await getMediaForQuery(
        baseName,
        mediaTypes: ['image', 'video'],
      );

      // Look for files with similar names and same extension
      for (final result in searchResults) {
        final resultPath = Uri.parse(result['file_uri'] as String).path;
        final resultBaseName = path.basenameWithoutExtension(resultPath);

        if (path.extension(resultPath).toLowerCase() ==
                extension.toLowerCase() &&
            (resultBaseName.contains(baseName) ||
                baseName.contains(resultBaseName))) {
          if (config.verboseLogging) {
            print(
                '✅ MediaCoordinator: Recovered by filename pattern: ${result['file_uri']}');
          }
          return result['file_uri'] as String;
        }
      }
      return null;
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Filename pattern recovery failed: $e');
      }
      return null;
    }
  }

  /// Recovery Strategy 3: Search by metadata birthprint (creation time + file size)
  Future<String?> _recoverByMetadata(
      String originalPath, MediaValidationConfig config) async {
    try {
      // Extract birthprint from original file or cache
      final originalBirthprint = await _extractFileBirthprint(originalPath);
      if (originalBirthprint == null) return null;

      // Search for matching files using birthprint
      final candidates =
          await _findFilesByBirthprint(originalBirthprint, config);

      if (candidates.isEmpty) return null;

      // Find best match using similarity scoring
      final bestMatch =
          _selectBestBirthprintMatch(candidates, originalBirthprint, config);

      if (bestMatch != null && config.verboseLogging) {
        print(
            '✅ MediaCoordinator: Recovered by metadata birthprint: $bestMatch');
      }

      return bestMatch;
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Metadata recovery failed: $e');
      }
      return null;
    }
  }

  /// Extract file birthprint from path or cached metadata
  Future<MediaBirthprint?> _extractFileBirthprint(String filePath) async {
    try {
      // Check cache first for performance
      final cacheKey = filePath.hashCode.toString();
      if (_birthprintCache.containsKey(cacheKey)) {
        return _birthprintCache[cacheKey];
      }

      // Try to extract from file system if file exists
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        final filename = path.basename(filePath);

        final birthprint = MediaBirthprint(
          creationTime: stat.modified,
          fileSize: stat.size,
          originalFilename: filename,
        );

        // Cache for future use
        _birthprintCache[cacheKey] = birthprint;
        return birthprint;
      }

      // Try to extract from PhotoManager metadata if available
      final pmBirthprint = await _extractBirthprintFromPhotoManager(filePath);
      if (pmBirthprint != null) {
        _birthprintCache[cacheKey] = pmBirthprint;
      }

      return pmBirthprint;
    } catch (e) {
      return null;
    }
  }

  /// Extract birthprint from PhotoManager asset metadata
  Future<MediaBirthprint?> _extractBirthprintFromPhotoManager(
      String filePath) async {
    try {
      // Search PhotoManager assets for matching path
      final searchResults =
          await getMediaForQuery('', mediaTypes: ['image', 'video']);

      for (final result in searchResults) {
        if (result['file_uri'] == filePath) {
          final createdAt = result['created_at'] as DateTime?;
          final fileSize = result['file_size'] as int?;
          final filename = path.basename(filePath);

          if (createdAt != null && fileSize != null) {
            return MediaBirthprint(
              creationTime: createdAt,
              fileSize: fileSize,
              originalFilename: filename,
            );
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Find files with matching birthprint across all accessible directories
  Future<List<Map<String, dynamic>>> _findFilesByBirthprint(
    MediaBirthprint targetBirthprint,
    MediaValidationConfig config,
  ) async {
    final candidates = <Map<String, dynamic>>[];

    try {
      // Get all media files from PhotoManager
      final allMedia =
          await getMediaForQuery('', mediaTypes: ['image', 'video']);

      for (final mediaItem in allMedia) {
        final filePath = mediaItem['file_uri'] as String;
        final candidateBirthprint =
            await _extractFileBirthprint(Uri.parse(filePath).path);

        if (candidateBirthprint != null) {
          final similarity = targetBirthprint.similarityTo(candidateBirthprint);

          if (similarity >= config.metadataMatchThreshold) {
            candidates.add({
              'file_uri': filePath,
              'birthprint': candidateBirthprint,
              'similarity': similarity,
              'metadata': mediaItem,
            });
          }
        }
      }

      // Sort by similarity score (highest first)
      candidates.sort((a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double));
    } catch (e) {
      // Return empty list on error
    }

    return candidates;
  }

  /// Select best match from birthprint candidates using advanced scoring
  String? _selectBestBirthprintMatch(
    List<Map<String, dynamic>> candidates,
    MediaBirthprint targetBirthprint,
    MediaValidationConfig config,
  ) {
    if (candidates.isEmpty) return null;

    // Get the highest scoring candidate
    final bestCandidate = candidates.first;
    final similarity = bestCandidate['similarity'] as double;

    // Only return if similarity meets threshold
    if (similarity >= config.metadataMatchThreshold) {
      return bestCandidate['file_uri'] as String;
    }

    return null;
  }

  /// Recovery Strategy 4: Force comprehensive cache refresh and retry
  Future<String?> _recoverAfterCacheRefresh(
      String brokenUri, MediaValidationConfig config) async {
    try {
      // After comprehensive refresh, check if the original URI is now valid
      final isNowValid = await validateMediaURI(brokenUri);
      if (isNowValid) {
        if (config.verboseLogging) {
          print(
              '✅ MediaCoordinator: URI recovered after cache refresh: $brokenUri');
        }
        return brokenUri;
      }
      return null;
    } catch (e) {
      if (config.verboseLogging) {
        print('❌ MediaCoordinator: Cache refresh recovery failed: $e');
      }
      return null;
    }
  }

  /// Force comprehensive cache refresh across all layers with intelligent purging
  Future<void> _forceComprehensiveCacheRefresh() async {
    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting comprehensive cache refresh...');
      }

      // Step 1: Purge stale references first for efficiency
      await purgeStaleReferences(forceFullPurge: true);

      // Step 2: Clear all PhotoManager caches with proper sequencing
      await PhotoManager.clearFileCache();
      await PhotoManager.releaseCache();

      // Step 3: Reset change notifications with optimized timing
      try {
        await PhotoManager.stopChangeNotify();
        await Future.delayed(const Duration(milliseconds: 500));
        await PhotoManager.startChangeNotify();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ MediaCoordinator: Change notification reset failed: $e');
        }
      }

      // Step 4: Force PhotoManager to rebuild its internal state with smart retry
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          await PhotoManager.getAssetPathList(
            type: RequestType.all,
            filterOption: FilterOptionGroup(
              imageOption: const FilterOption(
                sizeConstraint: SizeConstraint(ignoreSize: true),
              ),
              videoOption: const FilterOption(
                sizeConstraint: SizeConstraint(ignoreSize: true),
              ),
            ),
          );

          // Success, break retry loop
          break;
        } catch (e) {
          if (kDebugMode) {
            print(
                '⚠️ MediaCoordinator: PhotoManager rebuild attempt ${attempt + 1} failed: $e');
          }
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      // Step 5: Refresh internal service caches
      await _metadataService.refreshCache();
      await _mediaSearchService.initialize();

      // Step 6: Clear validation and birthprint caches for fresh start
      _validationCache.clear();
      _birthprintCache.clear();
      _staleUriReferences.clear();

      if (kDebugMode) {
        print('✅ MediaCoordinator: Comprehensive cache refresh completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Comprehensive cache refresh failed: $e');
      }
    }
  }

  /// Creates a recovered MediaItem from validation result
  MediaItem? createRecoveredMediaItem(
      MediaItem original, MediaValidationResult validationResult) {
    if (!validationResult.isValid || validationResult.recoveredUri == null) {
      return null;
    }

    return MediaItem(
      fileUri: validationResult.recoveredUri!,
      mimeType: original.mimeType,
      deviceMetadata: original.deviceMetadata,
    );
  }

  /// Convenience method to validate and recover a single MediaItem
  Future<MediaItem?> validateAndRecoverMediaItem(
    MediaItem mediaItem, {
    MediaValidationConfig config = const MediaValidationConfig(),
  }) async {
    final result =
        await validateAndRecoverMediaURI(mediaItem.fileUri, config: config);
    return createRecoveredMediaItem(mediaItem, result);
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print(
          '🗑️ MediaCoordinator: Being disposed (initialized: $_isInitialized)');
    }
    super.dispose();
  }

  /// ========== PHASE 1: CONSOLIDATED DIRECTORY SCANNING ==========

  /// Single source of truth for directory scanning across the entire application
  /// This method replaces all individual directory scanning in MediaMetadataService,
  /// DirectorySelectionScreen, and other components
  Future<void> refreshDirectoryData({
    List<String>? specificDirectories,
    bool forceFullScan = false,
    bool enableSmartCaching = true,
  }) async {
    if (_isDirectoryScanning && !forceFullScan) {
      // Wait for ongoing scan to complete unless force is requested
      while (_isDirectoryScanning) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isDirectoryScanning = true;

    try {
      if (kDebugMode) {
        print('🔄 MediaCoordinator: Starting consolidated directory scan');
        print('   Force full scan: $forceFullScan');
        print('   Smart caching: $enableSmartCaching');
        print(
            '   Specific directories: ${specificDirectories?.length ?? 'all'}');
      }

      final startTime = DateTime.now();

      // Get directories to scan
      final directoriesToScan = specificDirectories ??
          (isCustomDirectoriesEnabled
              ? _directoryService.enabledDirectories.map((d) => d.path).toList()
              : DirectoryService.getPlatformDefaults()
                  .map((d) => d.path)
                  .toList());

      // Phase 1a: Smart change detection (skip if forcing full scan)
      final changedDirectories = <String>[];
      if (!forceFullScan && enableSmartCaching) {
        for (final dirPath in directoriesToScan) {
          if (await _needsDirectoryRescan(dirPath)) {
            changedDirectories.add(dirPath);
          }
        }

        if (changedDirectories.isEmpty) {
          if (kDebugMode) {
            print(
                '✅ MediaCoordinator: No directory changes detected, using cache');
          }
          return;
        }

        if (kDebugMode) {
          print(
              '📁 MediaCoordinator: Detected changes in ${changedDirectories.length} directories');
        }
      } else {
        changedDirectories.addAll(directoriesToScan);
      }

      // Phase 1b: Consolidated directory scanning with parallel processing
      final scanResults =
          await _performConsolidatedDirectoryScan(changedDirectories);

      // Phase 1c: Update unified cache system
      await _updateUnifiedDirectoryCache(scanResults);

      // Phase 1d: Notify dependent services of changes
      await _notifyServicesOfDirectoryChanges(changedDirectories);

      final duration = DateTime.now().difference(startTime);
      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: Consolidated directory scan completed in ${duration.inMilliseconds}ms');
        print('   Scanned ${changedDirectories.length} directories');
        print(
            '   Found ${scanResults.values.fold(0, (sum, list) => sum + list.length)} media files');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Consolidated directory scan failed: $e');
      }
      rethrow;
    } finally {
      _isDirectoryScanning = false;
    }
  }

  /// Performs the actual directory scanning with optimized parallel processing
  Future<Map<String, List<MediaFileInfo>>> _performConsolidatedDirectoryScan(
    List<String> directoriesToScan,
  ) async {
    final scanResults = <String, List<MediaFileInfo>>{};

    // Process directories in parallel batches for optimal performance
    const maxConcurrentScans = 3;
    for (int i = 0; i < directoriesToScan.length; i += maxConcurrentScans) {
      final batch = directoriesToScan.skip(i).take(maxConcurrentScans);

      final batchResults = await Future.wait(
        batch.map((dirPath) => _scanSingleDirectory(dirPath)),
      );

      // Merge batch results
      for (int j = 0; j < batchResults.length; j++) {
        final dirPath = batch.elementAt(j);
        scanResults[dirPath] = batchResults[j];
      }
    }

    return scanResults;
  }

  /// Scans a single directory with comprehensive metadata extraction
  Future<List<MediaFileInfo>> _scanSingleDirectory(String directoryPath) async {
    final mediaFiles = <MediaFileInfo>[];

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        if (kDebugMode) {
          print(
              '⚠️ MediaCoordinator: Directory does not exist: $directoryPath');
        }
        return mediaFiles;
      }

      await for (final entity in directory.list()) {
        if (entity is File && _isSupportedMediaFile(entity.path)) {
          try {
            final fileInfo = await _extractMediaFileInfo(entity);
            if (fileInfo != null) {
              mediaFiles.add(fileInfo);
            }
          } catch (e) {
            if (kDebugMode) {
              print(
                  '⚠️ MediaCoordinator: Failed to process ${entity.path}: $e');
            }
            // Continue with other files
          }
        }
      }

      // Update directory timestamp after successful scan
      _directoryTimestamps[directoryPath] = DateTime.now();
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaCoordinator: Failed to scan directory $directoryPath: $e');
      }
    }

    return mediaFiles;
  }

  /// Extracts comprehensive media file information for the unified cache
  Future<MediaFileInfo?> _extractMediaFileInfo(File file) async {
    try {
      final stats = await file.stat();
      final fileName = path.basename(file.path);
      final extension = path.extension(file.path).toLowerCase();

      // Basic file information
      final fileInfo = MediaFileInfo(
        filePath: file.path,
        fileName: fileName,
        fileUri: file.uri.toString(),
        mimeType: _getMimeTypeFromPath(file.path),
        fileSize: stats.size,
        lastModified: stats.modified,
        extension: extension,
      );

      // Extract metadata using the existing metadata service
      try {
        final metadata = await _metadataService.extractMetadata(file);
        fileInfo.enrichWithMetadata(metadata);
      } catch (e) {
        // Continue without metadata if extraction fails
        if (kDebugMode) {
          print(
              '⚠️ MediaCoordinator: Metadata extraction failed for ${file.path}: $e');
        }
      }

      return fileInfo;
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaCoordinator: Failed to extract file info for ${file.path}: $e');
      }
      return null;
    }
  }

  /// Updates the unified directory cache with scan results
  Future<void> _updateUnifiedDirectoryCache(
      Map<String, List<MediaFileInfo>> scanResults) async {
    for (final entry in scanResults.entries) {
      final directoryPath = entry.key;
      final mediaFiles = entry.value;

      // Create or update directory cache entry
      _unifiedDirectoryCache[directoryPath] = DirectoryCache(
        directoryPath: directoryPath,
        mediaFiles: mediaFiles,
        lastScanned: DateTime.now(),
        fileCount: mediaFiles.length,
      );

      // Update file cache for rename detection
      _directoryFileCache[directoryPath] =
          mediaFiles.map((f) => f.fileName).toList();
    }

    if (kDebugMode) {
      print(
          '📊 MediaCoordinator: Updated unified cache for ${scanResults.length} directories');
    }
  }

  /// Notifies dependent services of directory changes
  Future<void> _notifyServicesOfDirectoryChanges(
      List<String> changedDirectories) async {
    try {
      // Notify MediaMetadataService to update its cache from our unified cache
      // This eliminates the need for MediaMetadataService to scan directories independently
      await _syncMetadataServiceCache();

      // Notify MediaSearchService if it needs to rebuild indices
      if (changedDirectories.isNotEmpty) {
        await _mediaSearchService.initialize();
      }

      // Notify listeners of changes
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ MediaCoordinator: Failed to notify services of changes: $e');
      }
    }
  }

  /// Syncs MediaMetadataService cache with our unified directory cache
  /// This eliminates redundant scanning in MediaMetadataService
  Future<void> _syncMetadataServiceCache() async {
    try {
      // Build the metadata cache structure that MediaMetadataService expects
      final mediaItems = <String, Map<String, dynamic>>{};
      final mediaByDate = <String, List<String>>{};
      final mediaByFolder = <String, List<String>>{};
      final mediaByLocation = <String, List<String>>{};
      final directoriesInfo = <String, Map<String, dynamic>>{};

      // Process each directory in our unified cache
      for (final entry in _unifiedDirectoryCache.entries) {
        final directoryPath = entry.key;
        final directoryCache = entry.value;

        // Directory info
        final directory = _directoryService.enabledDirectories.firstWhere(
            (d) => d.path == directoryPath,
            orElse: () => MediaDirectory(
                id: 'temp',
                displayName: path.basename(directoryPath),
                path: directoryPath,
                isDefault: false,
                isEnabled: true));

        directoriesInfo[directoryPath] = {
          'name': directory.displayName,
          'path': directoryPath,
          'media_count': directoryCache.fileCount,
        };

        // File info
        final folderMediaIds = <String>[];
        for (final mediaFile in directoryCache.mediaFiles) {
          final mediaId = mediaFile.filePath;
          folderMediaIds.add(mediaId);

          // Convert our MediaFileInfo to the format expected by MediaMetadataService
          mediaItems[mediaId] = mediaFile.toMetadataServiceFormat();

          // Add to date indices
          if (mediaFile.creationDate != null) {
            final dateKey =
                mediaFile.creationDate!.toIso8601String().split('T')[0];
            mediaByDate.putIfAbsent(dateKey, () => []).add(mediaId);
          }

          // Add to location indices
          if (mediaFile.latitude != null && mediaFile.longitude != null) {
            final locationKey =
                'location_${mediaFile.latitude}_${mediaFile.longitude}';
            mediaByLocation.putIfAbsent(locationKey, () => []).add(mediaId);
          }
        }

        mediaByFolder[directoryPath] = folderMediaIds;
      }

      // Update MediaMetadataService cache directly (bypassing its scanning)
      await _metadataService.updateCacheFromExternalSource({
        'media_items': mediaItems,
        'media_by_date': mediaByDate,
        'media_by_folder': mediaByFolder,
        'media_by_location': mediaByLocation,
        'directories': directoriesInfo,
        'last_update': DateTime.now().toIso8601String(),
      });

      if (kDebugMode) {
        print(
            '🔄 MediaCoordinator: Synced ${mediaItems.length} items to MediaMetadataService cache');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ MediaCoordinator: Failed to sync metadata service cache: $e');
      }
    }
  }

  /// Gets directory information from the unified cache
  DirectoryCache? getDirectoryCache(String directoryPath) {
    return _unifiedDirectoryCache[directoryPath];
  }

  /// Gets all cached directory information
  Map<String, DirectoryCache> get allDirectoryCaches =>
      Map.from(_unifiedDirectoryCache);

  /// Clears directory caches for specific directories or all
  void clearDirectoryCache({List<String>? specificDirectories}) {
    if (specificDirectories != null) {
      for (final dirPath in specificDirectories) {
        _unifiedDirectoryCache.remove(dirPath);
        _directoryFileCache.remove(dirPath);
        _directoryTimestamps.remove(dirPath);
      }
    } else {
      _unifiedDirectoryCache.clear();
      _directoryFileCache.clear();
      _directoryTimestamps.clear();
    }

    if (kDebugMode) {
      print(
          '🗑️ MediaCoordinator: Cleared directory cache for ${specificDirectories?.length ?? 'all'} directories');
    }
  }

  /// ========== PHASE 2: UNIFIED MEDIA VALIDATION SYSTEM ==========

  /// Central validation method that replaces all scattered validation calls
  /// This method should be used by ALL components that need to validate media
  Future<MediaValidationBatchResult> validateMediaBatch(
    List<String> mediaUris, {
    MediaValidationConfig config = const MediaValidationConfig(),
    bool enableRecovery = true,
    bool enableCaching = true,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    if (kDebugMode && config.verboseLogging) {
      print(
          '🔍 MediaCoordinator: Starting unified media validation for ${mediaUris.length} items');
    }

    final results = <MediaValidationResult>[];
    final startTime = DateTime.now();

    // Process URIs in parallel batches for optimal performance
    const maxConcurrentValidations = 5;
    for (int i = 0; i < mediaUris.length; i += maxConcurrentValidations) {
      final batch = mediaUris.skip(i).take(maxConcurrentValidations);

      final batchResults = await Future.wait(
        batch.map((uri) => _validateSingleMediaUri(
              uri,
              config: config,
              enableRecovery: enableRecovery,
              enableCaching: enableCaching,
            )),
      );

      results.addAll(batchResults);
    }

    final batchResult = MediaValidationBatchResult(results: results);
    final duration = DateTime.now().difference(startTime);

    if (kDebugMode && config.verboseLogging) {
      print(
          '✅ MediaCoordinator: Unified validation completed in ${duration.inMilliseconds}ms');
      print('   Valid: ${batchResult.validItems}');
      print('   Recovered: ${batchResult.recoveredItems}');
      print('   Failed: ${batchResult.failedItems}');
    }

    return batchResult;
  }

  /// Validates a single media URI with comprehensive caching and recovery
  Future<MediaValidationResult> _validateSingleMediaUri(
    String uri, {
    required MediaValidationConfig config,
    required bool enableRecovery,
    required bool enableCaching,
  }) async {
    // Check cache first if enabled
    if (enableCaching) {
      final cachedResult = _getValidationFromCache(uri);
      if (cachedResult != null) {
        return cachedResult;
      }
    }

    // Perform validation
    MediaValidationResult result;
    try {
      // Step 1: Basic URI and file existence validation
      if (!_isValidMediaURI(uri)) {
        result = MediaValidationResult(
          isValid: false,
          originalUri: uri,
          recoveredUri: null,
          recoveryMethod: MediaRecoveryMethod.failed,
          errorMessage: 'Invalid URI format',
        );
      } else {
        final filePath = Uri.parse(uri).path;
        final file = File(filePath);

        if (await file.exists()) {
          // Step 2: Directory compliance validation
          final isAllowed =
              await isFileAllowedByCurrentDirectoryState(filePath);
          if (!isAllowed) {
            result = MediaValidationResult(
              isValid: false,
              originalUri: uri,
              recoveredUri: null,
              recoveryMethod: MediaRecoveryMethod.failed,
              errorMessage: 'File not in enabled directories',
            );
          } else {
            // Step 3: File integrity validation
            final isIntegrityValid = await _validateFileIntegrity(file);
            if (isIntegrityValid) {
              result = MediaValidationResult(
                isValid: true,
                originalUri: uri,
                recoveredUri: uri,
                recoveryMethod: MediaRecoveryMethod.none,
              );
            } else {
              result = MediaValidationResult(
                isValid: false,
                originalUri: uri,
                recoveredUri: null,
                recoveryMethod: MediaRecoveryMethod.failed,
                errorMessage: 'File integrity check failed',
              );
            }
          }
        } else {
          // File doesn't exist - attempt recovery if enabled
          if (enableRecovery) {
            result = await _attemptMediaRecovery(uri, config);
          } else {
            result = MediaValidationResult(
              isValid: false,
              originalUri: uri,
              recoveredUri: null,
              recoveryMethod: MediaRecoveryMethod.failed,
              errorMessage: 'File does not exist',
            );
          }
        }
      }
    } catch (e) {
      result = MediaValidationResult(
        isValid: false,
        originalUri: uri,
        recoveredUri: null,
        recoveryMethod: MediaRecoveryMethod.failed,
        errorMessage: 'Validation error: $e',
      );
    }

    // Cache result if enabled
    if (enableCaching) {
      _cacheValidationResult(uri, result);
    }

    return result;
  }

  /// Validates file integrity (format, size, readability)
  Future<bool> _validateFileIntegrity(File file) async {
    try {
      // Check file size
      final size = await file.length();
      if (size == 0) return false;

      // Check MIME type
      final mimeType = _getMimeTypeFromPath(file.path);
      if (!_isSupportedMediaType(mimeType)) return false;

      // For images, validate headers
      if (mimeType.startsWith('image/')) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return false;
        return _hasValidImageHeader(bytes, mimeType);
      }

      // For videos, basic existence check is sufficient for now
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gets validation result from cache
  MediaValidationResult? _getValidationFromCache(String uri) {
    final cacheEntry = _validationCache[uri];
    if (cacheEntry != null && cacheEntry.isValid) {
      return cacheEntry.result;
    }
    return null;
  }

  /// Unified validation method for screens and services
  /// This replaces individual validation calls in MediaSelectionScreen, HistoryScreen, etc.
  Future<List<Map<String, dynamic>>> validateAndFilterMediaCandidates(
    List<Map<String, dynamic>> candidates, {
    MediaValidationConfig? config,
    bool showProgress = false,
  }) async {
    if (candidates.isEmpty) return candidates;

    final validationConfig = config ?? MediaValidationConfig.production;
    final validatedCandidates = <Map<String, dynamic>>[];
    final urisToValidate =
        candidates.map((c) => c['file_uri'] as String).toList();

    // Perform batch validation
    final batchResult = await validateMediaBatch(
      urisToValidate,
      config: validationConfig,
      enableRecovery: true,
      enableCaching: true,
    );

    // Process results and update candidates
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final validationResult = batchResult.results[i];

      if (validationResult.isValid) {
        // Update candidate with recovered URI if needed
        if (validationResult.wasRecovered) {
          candidate['file_uri'] = validationResult.effectiveUri;
          candidate['_recovered'] = true;
        }
        validatedCandidates.add(candidate);
      }
    }

    // Purge stale references from excluded candidates
    final excludedCount = candidates.length - validatedCandidates.length;
    if (excludedCount > 0) {
      final brokenUris = candidates
          .where((c) =>
              !validatedCandidates.any((v) => v['file_uri'] == c['file_uri']))
          .map((c) => c['file_uri'] as String)
          .toList();

      // Purge stale references in background
      _purgeStaleReferencesAsync(brokenUris);

      if (kDebugMode) {
        print(
            '🧹 MediaCoordinator: Excluded $excludedCount broken media items from candidates');
      }
    }

    return validatedCandidates;
  }

  /// ========== PHASE 4: CONSOLIDATED REFRESH PIPELINE ==========

  /// Single entry point for all media refresh operations across the app
  /// This method replaces all individual refresh calls in screens and services
  Future<void> notifyMediaChange({
    List<String>? changedDirectories,
    bool forceFullRefresh = false,
    String? source,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'MediaCoordinator not initialized. Call initialize() first.');
    }

    try {
      if (kDebugMode) {
        print('🔔 MediaCoordinator: Media change notification received');
        print('   Source: ${source ?? 'unknown'}');
        print('   Force full refresh: $forceFullRefresh');
        print('   Changed directories: ${changedDirectories?.length ?? 'all'}');
      }

      final startTime = DateTime.now();

      // Step 1: Refresh directory data with smart caching
      await refreshDirectoryData(
        specificDirectories: changedDirectories,
        forceFullScan: forceFullRefresh,
        enableSmartCaching: !forceFullRefresh,
      );

      // Step 2: Clear PhotoManager caches if needed
      if (forceFullRefresh) {
        await PhotoManager.clearFileCache();
        await PhotoManager.releaseCache();
      }

      // Step 3: Clear validation caches for affected directories
      if (changedDirectories != null) {
        _clearValidationCacheForDirectories(changedDirectories);
      } else if (forceFullRefresh) {
        _validationCache.clear();
        _birthprintCache.clear();
      }

      // Step 4: Notify all listeners
      notifyListeners();

      final duration = DateTime.now().difference(startTime);
      if (kDebugMode) {
        print(
            '✅ MediaCoordinator: Media change notification processed in ${duration.inMilliseconds}ms');
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaCoordinator: Failed to process media change notification: $e');
      }
      rethrow;
    }
  }

  /// Clears validation cache for specific directories
  void _clearValidationCacheForDirectories(List<String> directoryPaths) {
    final urisToRemove = <String>[];

    for (final entry in _validationCache.entries) {
      final uri = entry.key;
      try {
        final filePath = Uri.parse(uri).path;
        for (final dirPath in directoryPaths) {
          if (filePath.startsWith(dirPath)) {
            urisToRemove.add(uri);
            break;
          }
        }
      } catch (e) {
        // Skip invalid URIs
      }
    }

    for (final uri in urisToRemove) {
      _validationCache.remove(uri);
    }

    if (kDebugMode && urisToRemove.isNotEmpty) {
      print(
          '🗑️ MediaCoordinator: Cleared ${urisToRemove.length} validation cache entries for changed directories');
    }
  }

  /// Provides consolidated media statistics for debugging and monitoring
  Map<String, dynamic> getMediaSystemStatus() {
    final directoryCount = _unifiedDirectoryCache.length;
    final totalFiles = _unifiedDirectoryCache.values
        .fold(0, (sum, cache) => sum + cache.fileCount);
    final validationCacheSize = _validationCache.length;
    final staleReferencesCount = _staleUriReferences.length;

    return {
      'is_initialized': _isInitialized,
      'custom_directories_enabled': isCustomDirectoriesEnabled,
      'enabled_directories_count': enabledDirectories.length,
      'cached_directories_count': directoryCount,
      'total_cached_files': totalFiles,
      'validation_cache_size': validationCacheSize,
      'stale_references_count': staleReferencesCount,
      'last_directory_scan': _directoryTimestamps.values.isNotEmpty
          ? _directoryTimestamps.values
              .reduce((a, b) => a.isAfter(b) ? a : b)
              .toIso8601String()
          : null,
      'cache_status':
          _unifiedDirectoryCache.map((path, cache) => MapEntry(path, {
                'file_count': cache.fileCount,
                'last_scanned': cache.lastScanned.toIso8601String(),
                'is_valid': cache.isValid,
              })),
    };
  }
}
