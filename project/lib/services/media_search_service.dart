import 'dart:async';
import 'package:flutter/foundation.dart';
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

  // Initialize the media index
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permission
      final PermissionState permissionState = await PhotoManager.requestPermissionExtend();
      if (!permissionState.hasAccess) {
        throw Exception('Media access permission denied');
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

      // Get all assets
      final int assetCount = await allPhotosAlbum.assetCountAsync;
      final List<AssetEntity> assets = await allPhotosAlbum.getAssetListRange(
        start: 0,
        end: assetCount,
      );

      // Build the media index
      _mediaIndex = await _buildMediaIndex(assets);
      _isInitialized = true;
    } catch (e) {
      print('Error initializing media index: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  // Build the media index from asset entities
  Future<List<LocalMedia>> _buildMediaIndex(List<AssetEntity> assets) async {
    final List<LocalMedia> mediaList = [];

    for (final asset in assets) {
      try {
        final File? file = await asset.file;
        if (file == null) continue;

        String mimeType;
        switch (asset.type) {
          case AssetType.image:
            mimeType = 'image/${path.extension(file.path).replaceAll('.', '')}';
            break;
          case AssetType.video:
            mimeType = 'video/${path.extension(file.path).replaceAll('.', '')}';
            break;
          default:
            continue; // Skip other types
        }

        // Read EXIF data for additional metadata
        Map<String, IfdTag>? exifData;
        try {
          exifData = await readExifFromFile(file);
        } catch (e) {
          // Continue without EXIF data
          print('Error reading EXIF: $e');
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
            fileSizeBytes: await file.length(),
            duration: asset.type == AssetType.video ? asset.duration : 0,
          ),
        );
      } catch (e) {
        print('Error processing asset ${asset.id}: $e');
        // Continue with next asset
      }
    }

    return mediaList;
  }

  // Find media candidates based on a query
  Future<List<LocalMedia>> findCandidates(String query) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Parse the query to extract filters
    final queryFilters = _parseQuery(query);

    // Apply filters to the media index
    final filteredMedia = _mediaIndex.where((media) {
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

      // Apply location filter
      if (queryFilters.location != null &&
          queryFilters.location!.isNotEmpty &&
          media.latitude != null &&
          media.longitude != null) {
        // Simple check for location keywords in the query
        // In a real app, you'd use a more sophisticated location matching system
        final locationLower = queryFilters.location!.toLowerCase();
        final filePathLower = media.fileUri.toLowerCase();
        if (!filePathLower.contains(locationLower)) {
          return false;
        }
      }

      // Apply time of day filter
      if (queryFilters.timeOfDay != null) {
        final hour = media.creationDateTime.hour;
        switch (queryFilters.timeOfDay!) {
          case TimeOfDay.morning:
            if (hour < 5 || hour > 11) return false;
            break;
          case TimeOfDay.afternoon:
            if (hour < 12 || hour > 17) return false;
            break;
          case TimeOfDay.evening:
            if (hour < 18 || hour > 21) return false;
            break;
          case TimeOfDay.night:
            if (hour > 4 && hour < 22) return false;
            break;
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
    }).toList();

    // Sort results
    filteredMedia.sort((a, b) {
      // 1. If location was specified, sort by proximity (not implemented here)
      // 2. Sort by recency (newest first)
      return b.creationDateTime.compareTo(a.creationDateTime);
    });

    // Return top 20 results
    return filteredMedia.take(20).toList();
  }

  // Convert LocalMedia objects to maps for UI
  List<Map<String, dynamic>> getCandidateMaps(List<LocalMedia> candidates) {
    return candidates.map((media) => {
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
    }).toList();
  }

  // Parse a query string into structured filters
  QueryFilters _parseQuery(String query) {
    final queryLower = query.toLowerCase();
    final filters = QueryFilters();

    // Extract date range
    filters.dateRange = _dateParser.extractDateRange(queryLower);

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

    // Extract time of day
    if (queryLower.contains('morning') || queryLower.contains('sunrise')) {
      filters.timeOfDay = TimeOfDay.morning;
    } else if (queryLower.contains('afternoon')) {
      filters.timeOfDay = TimeOfDay.afternoon;
    } else if (queryLower.contains('evening') || queryLower.contains('sunset')) {
      filters.timeOfDay = TimeOfDay.evening;
    } else if (queryLower.contains('night')) {
      filters.timeOfDay = TimeOfDay.night;
    }

    // Extract location (simplified)
    final locationKeywords = [
      'beach', 'park', 'mountain', 'lake', 'river', 'forest',
      'city', 'downtown', 'home', 'restaurant', 'cafe', 'school',
      'office', 'gym', 'mall', 'store', 'shop', 'hotel'
    ];
    
    for (final location in locationKeywords) {
      if (queryLower.contains(location)) {
        filters.location = location;
        break;
      }
    }

    // Extract other keywords
    final commonKeywords = [
      'sunset', 'sunrise', 'family', 'friends', 'party', 'vacation',
      'holiday', 'birthday', 'wedding', 'graduation', 'concert',
      'food', 'selfie', 'portrait', 'landscape', 'pet', 'dog', 'cat'
    ];
    
    for (final keyword in commonKeywords) {
      if (queryLower.contains(keyword)) {
        filters.keywords.add(keyword);
      }
    }

    return filters;
  }

  // Get an asset entity by ID
  Future<AssetEntity?> getAssetById(String id) async {
    try {
      return await AssetEntity.fromId(id);
    } catch (e) {
      print('Error getting asset by ID: $e');
      return null;
    }
  }

  // Read EXIF data from a file
  Future<Map<String, IfdTag>> readExifFromFile(File file) async {
    final bytes = await file.readAsBytes();
    return await readExifFromBytes(bytes);
  }
}

// Helper classes for query parsing
enum MediaType { photo, video }

enum TimeOfDay { morning, afternoon, evening, night }

class QueryFilters {
  DateTimeRange? dateRange;
  MediaType? mediaType;
  String? location;
  TimeOfDay? timeOfDay;
  List<String> keywords = [];
}

class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});
}