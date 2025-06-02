import 'dart:async';
import 'package:photo_manager/photo_manager.dart';
import 'package:exif/exif.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/date_parser.dart';

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

class MediaSearchService {
  List<LocalMedia> _mediaIndex = [];
  bool _isInitialized = false;
  final DateParser _dateParser = DateParser();

  // Initialize the media index with error handling
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permission
      final PermissionState permissionState =
          await PhotoManager.requestPermissionExtend();
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

      // Get the "All Photos" album
      final allPhotosAlbum = albums.firstWhere(
        (album) => album.isAll,
        orElse: () => albums.first,
      );

      // Get all assets with limit to prevent crashes
      final int assetCount = await allPhotosAlbum.assetCountAsync;
      final int limitedCount = assetCount > 1000
          ? 1000
          : assetCount; // Limit to 1000 for performance

      final List<AssetEntity> assets = await allPhotosAlbum.getAssetListRange(
        start: 0,
        end: limitedCount,
      );

      // Build the media index
      _mediaIndex = await _buildMediaIndex(assets);
      _isInitialized = true;
    } catch (e) {
      _isInitialized = true; // Mark as initialized to prevent retry loops
      _mediaIndex = []; // Use empty index
    }
  }

  // Build the media index from asset entities with error handling
  Future<List<LocalMedia>> _buildMediaIndex(List<AssetEntity> assets) async {
    final List<LocalMedia> mediaList = [];

    for (final asset in assets) {
      try {
        final File? file = await asset.file;
        if (file == null) continue;

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
            continue; // Skip other types
        }

        // Get file size with error handling
        int fileSize = 0;
        try {
          fileSize = await file.length();
        } catch (e) {
          // Ignore file size errors - continue with 0 size
        }

        mediaList.add(
          LocalMedia(
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
          ),
        );
      } catch (e) {
        // Continue with next asset
      }
    }

    return mediaList;
  }

  // Find media candidates based on a query with error handling
  Future<List<LocalMedia>> findCandidates(String query) async {
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
  List<Map<String, dynamic>> getCandidateMaps(List<LocalMedia> candidates) {
    try {
      return candidates
          .map((media) => {
                'id': media.id,
                'file_uri': media.fileUri,
                'mime_type': media.mimeType,
                'creation_time': media.creationDateTime.toIso8601String(),
                'latitude': media.latitude,
                'longitude': media.longitude,
                'width': media.width,
                'height': media.height,
                'is_video': media.isVideo,
                'duration': media.duration,
              })
          .toList();
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
}

// Helper classes for query parsing
enum MediaType { photo, video }

class QueryFilters {
  DateTimeRange? dateRange;
  MediaType? mediaType;
  List<String> keywords = [];
}
