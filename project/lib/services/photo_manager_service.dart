import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';

enum MediaType { photo, video }

class PhotoManagerService extends ChangeNotifier {
  Future<List<AssetEntity>> findAssetCandidates(
      Map<String, dynamic> searchParams) async {
    try {
      final List<AssetEntity> results = [];

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
          return terms.any((term) => title.contains(term.toLowerCase()));
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

    for (final asset in candidates) {
      try {
        // Get the actual file from the asset using PhotoManager's API
        final file = await asset.file;
        if (file != null) {
          // Get actual file size in bytes
          final fileSizeBytes = await file.length();

          results.add({
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
          });
        } else {
          // Fallback: try to construct a reasonable path, but log the issue
          if (kDebugMode) {
            print(
                '⚠️ Could not get file for asset ${asset.id}, using fallback path');
          }
          results.add({
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
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error getting file for asset ${asset.id}: $e');
        }
        // Skip this asset if we can't get its file
        continue;
      }
    }

    if (kDebugMode) {
      print(
          '🔍 PhotoManagerService: Converted ${candidates.length} assets to ${results.length} maps');
    }

    return results;
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
