import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';

enum MediaType { photo, video }

class PhotoManagerService extends ChangeNotifier {
  Future<List<AssetEntity>> findAssetCandidates(
      Map<String, dynamic> searchParams) async {
    try {
      final Map<String, AssetEntity> uniqueAssets =
          {}; // Use Map for deduplication

      // Extract search parameters
      final List<String> terms =
          (searchParams['terms'] as List<dynamic>?)?.cast<String>() ?? [];
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

      if (kDebugMode) {
        print(
            '🔍 PhotoManagerService: Found ${albums.length} albums to search');
      }

      // If directory is specified, only search in that directory
      if (directory != null) {
        final targetAlbum = albums.firstWhere(
          (album) => album.name == directory.split(Platform.pathSeparator).last,
          orElse: () => albums.first,
        );
        final assets = await targetAlbum.getAssetListRange(start: 0, end: 100);

        // Add to unique assets map to avoid duplicates even in single album
        for (final asset in assets) {
          uniqueAssets[asset.id] = asset;
        }

        if (kDebugMode) {
          print(
              '🔍 PhotoManagerService: Found ${assets.length} assets in directory "$directory"');
        }
      } else {
        // Search in all albums but deduplicate by asset ID
        for (final album in albums) {
          try {
            final assets = await album.getAssetListRange(start: 0, end: 100);

            // Add each asset to the map - duplicates will be automatically overwritten
            for (final asset in assets) {
              uniqueAssets[asset.id] = asset;
            }

            if (kDebugMode) {
              print(
                  '🔍 PhotoManagerService: Album "${album.name}" contributed ${assets.length} assets');
            }
          } catch (e) {
            if (kDebugMode) {
              print(
                  '⚠️ PhotoManagerService: Error reading album "${album.name}": $e');
            }
            // Continue with other albums if one fails
            continue;
          }
        }

        if (kDebugMode) {
          print(
              '🔍 PhotoManagerService: Total unique assets after deduplication: ${uniqueAssets.length}');
        }
      }

      // Convert back to list and sort by creation date (newest first)
      final results = uniqueAssets.values.toList();
      results.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      // Filter by search terms if provided
      if (terms.isNotEmpty) {
        final filteredResults = results.where((asset) {
          final title = asset.title?.toLowerCase() ?? '';
          return terms.any((term) => title.contains(term.toLowerCase()));
        }).toList();

        if (kDebugMode) {
          print(
              '🔍 PhotoManagerService: Filtered to ${filteredResults.length} assets matching search terms: ${terms.join(", ")}');
        }

        return filteredResults;
      }

      if (kDebugMode) {
        print(
            '🔍 PhotoManagerService: Returning ${results.length} deduplicated assets');
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

    for (final asset in candidates) {
      try {
        // Get the actual file from the asset using PhotoManager's API
        final file = await asset.file;
        if (file != null) {
          // Validate that this is a supported media file before processing
          final mimeType = _getMimeTypeFromFile(file);
          if (!_isSupportedMediaType(mimeType)) {
            if (kDebugMode) {
              print(
                  '⚠️ Skipping unsupported media type: ${file.path} ($mimeType)');
            }
            continue; // Skip unsupported files
          }

          // Additional validation: try to get file size to ensure file is accessible
          int fileSizeBytes;
          try {
            fileSizeBytes = await file.length();
            if (fileSizeBytes == 0) {
              if (kDebugMode) {
                print('⚠️ Skipping empty file: ${file.path}');
              }
              continue; // Skip empty files
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ Cannot access file: ${file.path} - $e');
            }
            continue; // Skip inaccessible files
          }

          results.add({
            'id': asset.id,
            'file_uri': file.uri.toString(),
            'mime_type': mimeType, // Use actual MIME type from file extension
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
          });
        } else {
          // For fallback case, we need to be more careful about MIME type detection
          final fallbackPath =
              '${asset.relativePath ?? ''}/${asset.title ?? asset.id}';
          final mimeType = _getMimeTypeFromPath(fallbackPath);

          if (!_isSupportedMediaType(mimeType)) {
            if (kDebugMode) {
              print(
                  '⚠️ Skipping unsupported fallback media type: $fallbackPath ($mimeType)');
            }
            continue; // Skip unsupported files
          }

          if (kDebugMode) {
            print(
                '⚠️ Could not get file for asset ${asset.id}, using fallback path');
          }

          results.add({
            'id': asset.id,
            'file_uri': 'file://$fallbackPath',
            'mime_type': mimeType, // Use detected MIME type
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
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error processing asset ${asset.id}: $e');
        }
        // Skip this asset if we can't process it
        continue;
      }
    }

    if (kDebugMode) {
      print(
          '🔍 PhotoManagerService: Filtered ${candidates.length} assets to ${results.length} valid media items');
    }

    return results;
  }

  /// Determines MIME type from actual file extension
  String _getMimeTypeFromFile(File file) {
    return _getMimeTypeFromPath(file.path);
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

  String _getMimeType(AssetEntity asset) {
    // This method is kept for backward compatibility but should not be used
    // Use _getMimeTypeFromFile or _getMimeTypeFromPath instead
    if (asset.type == AssetType.image) {
      return 'image/jpeg';
    } else if (asset.type == AssetType.video) {
      return 'video/mp4';
    } else {
      return 'application/octet-stream';
    }
  }
}
