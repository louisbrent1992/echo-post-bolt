import 'dart:async';
import 'package:photo_manager/photo_manager.dart';
import 'package:exif/exif.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/date_parser.dart';
import 'package:flutter/foundation.dart';

class LocalMedia {
  final String id;
  final String fileUri;
  final String mimeType;
  final DateTime creationDateTime;
  final double? latitude;
  final double? longitude;
  final int width;
  final int height;
  final int fileSizeBytes;
  final int duration; // 0 for photos, milliseconds for videos

  LocalMedia({
    required this.id,
    required this.fileUri,
    required this.mimeType,
    required this.creationDateTime,
    this.latitude,
    this.longitude,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.duration,
  });

  bool get isPhoto => duration == 0;
  bool get isVideo => duration > 0;
}

enum MediaType { photo, video }

class MediaSearchService extends ChangeNotifier {
  List<LocalMedia> _mediaIndex = [];
  bool _isInitialized = false;
  final DateParser _dateParser = DateParser();

  // Initialize the media index with error handling and album selection
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Check if we have permission without requesting it
      final PermissionState permissionState =
          await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      if (!permissionState.hasAccess) {
        _isInitialized = true; // Mark as initialized even without permission
        return;
      }

      // Get all albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );

      if (albums.isEmpty) {
        _isInitialized = true;
        return;
      }

      // Use "All Photos" album as default (no Firestore dependency)
      final selectedAlbumIds = await _getDefaultAlbumIds(albums);

      // Filter albums to only those selected
      final chosenAlbums =
          albums.where((album) => selectedAlbumIds.contains(album.id)).toList();

      // If no albums match (shouldn't happen), fallback to "All Photos"
      final List<AssetPathEntity> albumsToIndex;
      if (chosenAlbums.isEmpty) {
        final allPhotosAlbum = albums.firstWhere(
          (album) => album.isAll,
          orElse: () => albums.first,
        );
        albumsToIndex = [allPhotosAlbum];
      } else {
        albumsToIndex = chosenAlbums;
      }

      // Collect assets from all chosen albums
      final List<AssetEntity> allAssets = [];
      for (final album in albumsToIndex) {
        try {
          final int assetCount = await album.assetCountAsync;
          final int limitedCount = assetCount > 1000 ? 1000 : assetCount;

          if (limitedCount > 0) {
            final List<AssetEntity> albumAssets = await album.getAssetListRange(
              start: 0,
              end: limitedCount,
            );
            allAssets.addAll(albumAssets);
          }
        } catch (e) {
          // Continue with other albums if one fails
          continue;
        }
      }

      // Remove duplicates (same asset might be in multiple albums)
      final uniqueAssets = <String, AssetEntity>{};
      for (final asset in allAssets) {
        uniqueAssets[asset.id] = asset;
      }

      // Build the media index
      _mediaIndex = await _buildMediaIndex(uniqueAssets.values.toList());
      _isInitialized = true;
    } catch (e) {
      _isInitialized = true; // Mark as initialized to prevent retry loops
      _mediaIndex = []; // Use empty index
    }
  }

  // Get user-selected album IDs with fallback to "All Photos"
  Future<List<String>> _getDefaultAlbumIds(List<AssetPathEntity> albums) async {
    try {
      final allPhotosAlbum = albums.firstWhere(
        (album) => album.isAll,
        orElse: () => albums.first,
      );
      return [allPhotosAlbum.id];
    } catch (e) {
      return [];
    }
  }

  // Get all available albums on the device
  Future<List<AssetPathEntity>> getAvailableAlbums() async {
    try {
      final PermissionState permissionState =
          await PhotoManager.requestPermissionExtend();
      if (!permissionState.hasAccess) {
        return [];
      }

      return await PhotoManager.getAssetPathList(type: RequestType.common);
    } catch (e) {
      return [];
    }
  }

  // Re-initialize with new album selection
  Future<void> reinitializeWithAlbums(List<String> albumIds) async {
    _isInitialized = false;
    _mediaIndex = [];
    await initialize();
  }

  // Build the media index from asset entities with error handling
  Future<List<LocalMedia>> _buildMediaIndex(List<AssetEntity> assets) async {
    final List<LocalMedia> mediaList = [];

    if (assets.isEmpty) return mediaList;

    // FIXED: Process assets in batches with timeout protection
    const int batchSize = 10;
    const Duration timeout = Duration(seconds: 2);

    for (int i = 0; i < assets.length; i += batchSize) {
      final batch = assets.skip(i).take(batchSize).toList();

      // Process batch in parallel with timeout protection
      final batchResults = await Future.wait(
        batch.map((asset) => _buildMediaItemSafely(asset, timeout)),
        eagerError: false, // Continue even if some assets fail
      );

      // Add successful results
      for (final result in batchResults) {
        if (result != null) {
          mediaList.add(result);
        }
      }

      if (kDebugMode) {
        print(
            '🔄 MediaSearchService: Built index batch ${(i ~/ batchSize) + 1}/${(assets.length / batchSize).ceil()}, got ${batchResults.where((r) => r != null).length} valid media items');
      }
    }

    return mediaList;
  }

  /// Build a single LocalMedia item with error protection
  Future<LocalMedia?> _buildMediaItemSafely(
      AssetEntity asset, Duration timeout) async {
    try {
      final File? file = await asset.file;
      if (file == null) return null;

      String mimeType;
      switch (asset.type) {
        case AssetType.image:
          final ext =
              path.extension(file.path).replaceAll('.', '').toLowerCase();
          mimeType = 'image/${ext.isEmpty ? 'jpeg' : ext}';
          break;
        case AssetType.video:
          final ext =
              path.extension(file.path).replaceAll('.', '').toLowerCase();
          mimeType = 'video/${ext.isEmpty ? 'mp4' : ext}';
          break;
        default:
          return null; // Skip other types
      }

      // Get file size with error handling
      int fileSize = 0;
      try {
        fileSize = await file.length();
        if (fileSize == 0) {
          return null; // Skip empty files
        }
      } catch (e) {
        // Continue with 0 size rather than failing completely
      }

      return LocalMedia(
        id: asset.id,
        fileUri: file.uri.toString(),
        mimeType: mimeType,
        creationDateTime: asset.createDateTime,
        latitude: asset.latitude,
        longitude: asset.longitude,
        width: asset.width,
        height: asset.height,
        fileSizeBytes: fileSize,
        duration: asset.type == AssetType.video ? asset.duration : 0,
      );
    } catch (e) {
      // Skip problematic assets
      if (kDebugMode) {
        print(
            '⚠️ MediaSearchService: Skipping asset ${asset.id} due to error: $e');
      }
      return null;
    }
  }

  // Find media candidates based on a query with error handling
  Future<List<LocalMedia>> findLocalMediaCandidates(String query) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_mediaIndex.isEmpty) {
        return [];
      }

      // Parse the query to extract filters
      final queryFilters = _parseQuery(query);

      // Apply filters to the media index
      final filteredMedia = _mediaIndex.where((media) {
        try {
          // Apply date filter
          if (queryFilters.dateRange != null) {
            final start = queryFilters.dateRange!.start;
            final end = queryFilters.dateRange!.end;
            if (media.creationDateTime.isBefore(start) ||
                media.creationDateTime.isAfter(end)) {
              return false;
            }
          }

          // Apply media type filter
          if (queryFilters.mediaType != null) {
            if (queryFilters.mediaType == MediaType.photo && !media.isPhoto) {
              return false;
            }
            if (queryFilters.mediaType == MediaType.video && !media.isVideo) {
              return false;
            }
          }

          // Apply keyword filter
          if (queryFilters.keywords.isNotEmpty) {
            final filePathLower = media.fileUri.toLowerCase();
            final anyKeywordMatches = queryFilters.keywords.any(
              (keyword) => filePathLower.contains(keyword.toLowerCase()),
            );
            if (!anyKeywordMatches) {
              return false;
            }
          }

          return true;
        } catch (e) {
          return false;
        }
      }).toList();

      // Sort results by recency (newest first)
      try {
        filteredMedia
            .sort((a, b) => b.creationDateTime.compareTo(a.creationDateTime));
      } catch (e) {
        // Ignore sorting errors - continue with unsorted results
      }

      // Return top 20 results
      return filteredMedia.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  // Convert LocalMedia objects to maps for UI
  List<Map<String, dynamic>> getLocalMediaMaps(List<LocalMedia> candidates) {
    try {
      return candidates.map((media) {
        return {
          'id': media.id,
          'file_uri': media.fileUri,
          'mime_type': media.mimeType,
          'device_metadata': {
            'creation_time': media.creationDateTime.toIso8601String(),
            'latitude': media.latitude,
            'longitude': media.longitude,
            'orientation': 1, // or extract from EXIF if needed
            'width': media.width,
            'height': media.height,
            'file_size_bytes': media.fileSizeBytes,
            'duration': media.duration > 0
                ? media.duration / 1000.0
                : null, // Convert ms to seconds for video/audio
            'bitrate': null, // placeholder for future EXIF extraction
            'sampling_rate': null, // placeholder for audio metadata
            'frame_rate': null, // placeholder for video metadata
          },
          'upload_url': null, // placeholder for CDN upload URL
          'cdn_key': null, // placeholder for CDN key
          'caption': null, // placeholder for user to edit
          'is_video': media.isVideo,
          'duration': media.duration, // for UI sorting (in milliseconds)
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Parse a query string into structured filters
  QueryFilters _parseQuery(String query) {
    try {
      final queryLower = query.toLowerCase();
      final filters = QueryFilters();

      // Extract date range
      try {
        filters.dateRange = _dateParser.extractDateRange(queryLower);
      } catch (e) {
        // Ignore date parsing errors - continue without date filter
      }

      // Extract media type
      if (queryLower.contains('photo') ||
          queryLower.contains('image') ||
          queryLower.contains('picture')) {
        filters.mediaType = MediaType.photo;
      } else if (queryLower.contains('video') ||
          queryLower.contains('clip') ||
          queryLower.contains('movie')) {
        filters.mediaType = MediaType.video;
      }

      // Extract keywords
      final commonKeywords = [
        'sunset',
        'sunrise',
        'family',
        'friends',
        'party',
        'vacation',
        'holiday',
        'birthday',
        'wedding',
        'graduation',
        'concert',
        'food',
        'selfie',
        'portrait',
        'landscape',
        'pet',
        'dog',
        'cat'
      ];

      for (final keyword in commonKeywords) {
        if (queryLower.contains(keyword)) {
          filters.keywords.add(keyword);
        }
      }

      return filters;
    } catch (e) {
      return QueryFilters();
    }
  }

  // Get an asset entity by ID
  Future<AssetEntity?> getAssetById(String id) async {
    try {
      return await AssetEntity.fromId(id);
    } catch (e) {
      return null;
    }
  }

  // Read EXIF data from a file (simplified)
  Future<Map<String, IfdTag>?> readExifFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await readExifFromBytes(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<List<AssetEntity>> findAssetCandidates(
      Map<String, dynamic> searchParams) async {
    try {
      final List<AssetEntity> results = [];

      // Extract search parameters
      final List<String> terms =
          (searchParams['terms'] as List<dynamic>?)?.cast<String>() ?? [];
      final String originalQuery =
          searchParams['original_query'] as String? ?? '';
      final Map<String, dynamic>? dateRange =
          searchParams['date_range'] as Map<String, dynamic>?;
      final String? mediaType = searchParams['media_type'] as String?;
      final String? directory = searchParams['directory'] as String?;

      // Build filter options
      final filterOption = FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
          durationConstraint: DurationConstraint(
            max: Duration(minutes: 15),
          ),
        ),
        createTimeCond: dateRange != null
            ? DateTimeCond(
                min: DateTime.parse(dateRange['start'] as String),
                max: DateTime.parse(dateRange['end'] as String),
              )
            : null,
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false,
          ),
        ],
      );

      // Get all albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: mediaType?.toLowerCase() == 'video'
            ? RequestType.video
            : mediaType?.toLowerCase() == 'photo'
                ? RequestType.image
                : RequestType.all,
        filterOption: filterOption,
      );

      // If directory is specified, only search in that directory
      if (directory != null) {
        final targetAlbum = albums.firstWhere(
          (album) => album.name == directory.split(Platform.pathSeparator).last,
          orElse: () => albums.first,
        );
        final assets = await targetAlbum.getAssetListRange(start: 0, end: 100);
        results.addAll(assets);
      } else {
        // Search in all albums
        for (final album in albums) {
          final assets = await album.getAssetListRange(start: 0, end: 100);
          results.addAll(assets);
        }
      }

      // Filter by search terms if provided
      if (terms.isNotEmpty) {
        return results.where((asset) {
          final title = asset.title?.toLowerCase() ?? '';
          // Check both individual terms AND the complete original query for space-aware matching
          final originalQueryLower = originalQuery.toLowerCase().trim();
          return terms.any((term) => title.contains(term.toLowerCase())) ||
              (originalQueryLower.isNotEmpty &&
                  title.contains(originalQueryLower));
        }).toList();
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error finding media candidates: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAssetMaps(
      List<AssetEntity> candidates) async {
    final List<Map<String, dynamic>> results = [];

    if (candidates.isEmpty) return results;

    // FIXED: Process assets in batches with timeout and error isolation
    const int batchSize = 5;
    const Duration timeout = Duration(seconds: 3);

    for (int i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize).toList();

      // Process batch in parallel with timeout protection
      final batchResults = await Future.wait(
        batch.map((asset) => _processAssetSafely(asset, timeout)),
        eagerError: false, // Continue even if some assets fail
      );

      // Add successful results
      for (final result in batchResults) {
        if (result != null) {
          results.add(result);
        }
      }

      if (kDebugMode) {
        print(
            '🔄 MediaSearchService: Processed batch ${(i ~/ batchSize) + 1}/${(candidates.length / batchSize).ceil()}, got ${batchResults.where((r) => r != null).length} valid assets');
      }
    }

    if (kDebugMode) {
      print(
          '🔍 MediaSearchService: Converted ${candidates.length} assets to ${results.length} maps');
    }

    return results;
  }

  /// Process a single asset with error protection
  Future<Map<String, dynamic>?> _processAssetSafely(
      AssetEntity asset, Duration timeout) async {
    try {
      // Get the actual file from the asset using PhotoManager's API
      final file = await asset.file;
      if (file != null) {
        // Get actual file size in bytes with error handling
        int fileSizeBytes = 0;
        try {
          fileSizeBytes = await file.length();
          if (fileSizeBytes == 0) {
            if (kDebugMode) {
              print('⚠️ Skipping empty file: ${file.path}');
            }
            return null;
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Cannot access file size: ${file.path} - $e');
          }
          // Continue with 0 size rather than failing completely
        }

        return {
          'id': asset.id,
          'file_uri': file.uri.toString(),
          'mime_type': _getMimeType(asset),
          'device_metadata': {
            'creation_time': asset.createDateTime.toIso8601String(),
            'latitude': asset.latitude,
            'longitude': asset.longitude,
            'width': asset.width,
            'height': asset.height,
            'file_size_bytes': fileSizeBytes,
            'duration': asset.duration.toDouble(),
            'orientation': asset.orientation,
          }
        };
      } else {
        // Fallback: try to construct a reasonable path, but log the issue
        if (kDebugMode) {
          print(
              '⚠️ MediaSearchService: Could not get file for asset ${asset.id}, using fallback path');
        }
        return {
          'id': asset.id,
          'file_uri':
              'file://${asset.relativePath ?? ''}/${asset.title ?? asset.id}',
          'mime_type': _getMimeType(asset),
          'device_metadata': {
            'creation_time': asset.createDateTime.toIso8601String(),
            'latitude': asset.latitude,
            'longitude': asset.longitude,
            'width': asset.width,
            'height': asset.height,
            'file_size_bytes': 0, // Unknown file size for fallback
            'duration': asset.duration.toDouble(),
            'orientation': asset.orientation,
          }
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ MediaSearchService: Error getting file for asset ${asset.id}: $e');
      }
      return null; // Skip problematic assets
    }
  }

  String _getMimeType(AssetEntity asset) {
    if (asset.type == AssetType.image) {
      return 'image/jpeg';
    } else if (asset.type == AssetType.video) {
      return 'video/mp4';
    } else {
      return 'application/octet-stream';
    }
  }
}

// Helper classes for query parsing
class QueryFilters {
  DateTimeRange? dateRange;
  MediaType? mediaType;
  List<String> keywords = [];
}
