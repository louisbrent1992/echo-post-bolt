import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import 'directory_service.dart';

class MediaMetadataService extends ChangeNotifier {
  static const String _cache_file_name = 'media_metadata_cache.json';
  static const Duration _cache_refresh_interval = Duration(hours: 1);

  Map<String, dynamic> _metadata_cache = {};
  DateTime? _last_cache_update;
  bool _is_initialized = false;
  DirectoryService? _directory_service;

  // Getters
  bool get is_initialized => _is_initialized;
  DateTime? get last_cache_update => _last_cache_update;
  Map<String, dynamic> get metadata_cache => _metadata_cache;

  Future<void> initialize(DirectoryService directory_service) async {
    if (_is_initialized) return;

    _directory_service = directory_service;
    await _load_cache();
    _is_initialized = true;
    notifyListeners();
  }

  Future<void> _load_cache() async {
    try {
      final cache_dir = await getApplicationCacheDirectory();
      final cache_file = File(path.join(cache_dir.path, _cache_file_name));

      if (await cache_file.exists()) {
        final json_string = await cache_file.readAsString();
        _metadata_cache = json.decode(json_string);
        _last_cache_update =
            DateTime.parse(_metadata_cache['last_update'] ?? '');

        // Check if cache needs refresh
        if (_last_cache_update != null &&
            DateTime.now().difference(_last_cache_update!) >
                _cache_refresh_interval) {
          await refresh_cache();
        }
      } else {
        await refresh_cache();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading media metadata cache: $e');
      }
      _metadata_cache = {};
      await refresh_cache();
    }
  }

  Future<void> refresh_cache() async {
    if (_directory_service == null) {
      throw Exception('DirectoryService not initialized');
    }

    await _scan_directories();
    _last_cache_update = DateTime.now();

    // Save cache to file
    final cache_dir = await getApplicationCacheDirectory();
    final cache_file = File(path.join(cache_dir.path, _cache_file_name));
    await cache_file.writeAsString(json.encode(_metadata_cache));

    notifyListeners();
  }

  Future<void> _scan_directories() async {
    final directories = _directory_service!.enabledDirectories;
    final media_items = <String, Map<String, dynamic>>{};
    final media_by_date = <String, List<String>>{};
    final media_by_folder = <String, List<String>>{};
    final media_by_location = <String, List<String>>{};
    final directories_info = <String, Map<String, dynamic>>{};

    for (final directory in directories) {
      final dir_path = directory.path;
      directories_info[dir_path] = {
        'name': directory.displayName,
        'path': dir_path,
        'media_count': 0,
      };

      try {
        final dir = Directory(dir_path);
        if (await dir.exists()) {
          final files = await dir.list().toList();
          for (final file in files) {
            if (file is File && _is_media_file(file.path)) {
              final metadata = await _extract_media_metadata(file);
              if (metadata != null) {
                final media_id = file.path;
                media_items[media_id] = metadata;

                // Add to date index
                final date =
                    metadata['creation_time']?.toString().split('T')[0];
                if (date != null) {
                  media_by_date.putIfAbsent(date, () => []).add(media_id);
                }

                // Add to folder index
                media_by_folder.putIfAbsent(dir_path, () => []).add(media_id);

                // Add to location index if coordinates exist
                if (metadata['latitude'] != null &&
                    metadata['longitude'] != null) {
                  final location_key =
                      '${metadata['latitude']},${metadata['longitude']}';
                  media_by_location
                      .putIfAbsent(location_key, () => [])
                      .add(media_id);
                }

                directories_info[dir_path]!['media_count']++;
              }
            }
          }
        }
      } catch (e) {
        print('Error scanning directory $dir_path: $e');
      }
    }

    _metadata_cache = {
      'media_items': media_items,
      'media_by_date': media_by_date,
      'media_by_folder': media_by_folder,
      'media_by_location': media_by_location,
      'directories': directories_info,
    };

    await _save_cache();
  }

  bool _is_media_file(String extension) {
    const media_extensions = {
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
      '.webm',
      '.m4v',
      '.3gp',
      '.flv'
    };
    return media_extensions.contains(extension);
  }

  Future<Map<String, dynamic>?> _extract_media_metadata(File file) async {
    try {
      final stats = await file.stat();
      final mime_type =
          _get_mime_type_from_extension(path.extension(file.path));

      final metadata = <String, dynamic>{
        'id': path.basename(file.path),
        'file_uri': file.path,
        'mime_type': mime_type,
        'creation_time': stats.modified.toIso8601String(),
        'file_size_bytes': stats.size,
        'width': 0,
        'height': 0,
        'duration': 0,
        'folder': path.dirname(file.path),
      };

      if (mime_type.startsWith('image/')) {
        try {
          final bytes = await file.readAsBytes();
          final exif_data = await readExifFromBytes(bytes);

          if (exif_data.isNotEmpty) {
            // Extract GPS coordinates
            final gps_lat = exif_data['GPS GPSLatitude'];
            final gps_lon = exif_data['GPS GPSLongitude'];
            final gps_lat_ref = exif_data['GPS GPSLatitudeRef'];
            final gps_lon_ref = exif_data['GPS GPSLongitudeRef'];

            if (gps_lat != null && gps_lon != null) {
              final lat =
                  _parse_gps_coordinate(gps_lat, gps_lat_ref?.toString());
              final lon =
                  _parse_gps_coordinate(gps_lon, gps_lon_ref?.toString());
              if (lat != null) metadata['latitude'] = lat;
              if (lon != null) metadata['longitude'] = lon;
            }

            // Extract image dimensions
            final width = exif_data['Image ImageWidth'] ??
                exif_data['EXIF ExifImageWidth'];
            final height = exif_data['Image ImageLength'] ??
                exif_data['EXIF ExifImageLength'];

            if (width != null)
              metadata['width'] = int.tryParse(width.toString()) ?? 0;
            if (height != null)
              metadata['height'] = int.tryParse(height.toString()) ?? 0;

            // Extract creation date from EXIF
            final date_time = exif_data['Image DateTime'] ??
                exif_data['EXIF DateTimeOriginal'];
            if (date_time != null) {
              final date_string = date_time.toString();
              final formatted_date = date_string
                      .substring(0, 10)
                      .replaceAll(':', '-') +
                  (date_string.length > 10 ? date_string.substring(10) : '');
              final parsed_date = DateTime.tryParse(formatted_date);
              if (parsed_date != null) {
                metadata['creation_time'] = parsed_date.toIso8601String();
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

  void _add_to_cache(
      Map<String, dynamic> metadata, Map<String, dynamic> cache) {
    // Increment total media count
    cache['media_count'] = (cache['media_count'] as int) + 1;

    // Add to date-based index
    final date = metadata['creation_time'].toString().split('T')[0];
    if (!cache['media_by_date'].containsKey(date)) {
      cache['media_by_date'][date] = [];
    }
    cache['media_by_date'][date].add(metadata['id']);

    // Add to location-based index if coordinates exist
    if (metadata['latitude'] != null && metadata['longitude'] != null) {
      final location_key = '${metadata['latitude']},${metadata['longitude']}';
      if (!cache['media_by_location'].containsKey(location_key)) {
        cache['media_by_location'][location_key] = [];
      }
      cache['media_by_location'][location_key].add(metadata['id']);
    }

    // Add to folder-based index
    final folder = metadata['folder'];
    if (!cache['media_by_folder'].containsKey(folder)) {
      cache['media_by_folder'][folder] = [];
    }
    cache['media_by_folder'][folder].add(metadata['id']);

    // Update directory count
    final dir_path = path.dirname(metadata['file_uri']);
    if (cache['directories'].containsKey(dir_path)) {
      cache['directories'][dir_path]['media_count'] =
          (cache['directories'][dir_path]['media_count'] as int) + 1;
    }
  }

  String _get_mime_type_from_extension(String extension) {
    const mime_types = {
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
    return mime_types[extension.toLowerCase()] ?? 'application/octet-stream';
  }

  double? _parse_gps_coordinate(dynamic coordinate, String? reference) {
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
  Map<String, dynamic> get_media_context_for_ai() {
    if (!_is_initialized || _metadata_cache.isEmpty) {
      return {
        'media_context': {
          'recent_media': [],
          'directories': [],
          'total_count': 0
        }
      };
    }

    // Get recent media items
    final recent_media = get_recent_media(limit: 10)
        .map((item) => {
              'file_uri': item['file_uri'],
              'file_name': path.basename(item['file_uri']),
              'timestamp': item['creation_time'],
              'directory': item['folder'],
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
            })
        .toList();

    // Get directory information
    final directories = _metadata_cache['directories']
        .entries
        .map((entry) => {
              'name': entry.value['name'],
              'path': entry.value['path'],
              'media_count': entry.value['media_count']
            })
        .toList();

    return {
      'media_context': {
        'recent_media': recent_media,
        'directories': directories,
        'total_count': _metadata_cache['media_count'] ?? 0
      }
    };
  }

  Map<String, dynamic>? get_media_item(String media_id) {
    return _metadata_cache['media_items']?[media_id];
  }

  List<Map<String, dynamic>> get_media_by_date(String date) {
    final media_ids = _metadata_cache['media_by_date']?[date] ?? [];
    return media_ids
        .map((id) => get_media_item(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> get_media_by_folder(String folder_path) {
    final media_ids = _metadata_cache['media_by_folder']?[folder_path] ?? [];
    return media_ids
        .map((id) => get_media_item(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> get_media_by_location(
      double latitude, double longitude) {
    final location_key = '$latitude,$longitude';
    final media_ids = _metadata_cache['media_by_location']?[location_key] ?? [];
    return media_ids
        .map((id) => get_media_item(id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> get_recent_media({int limit = 10}) {
    final dates = _metadata_cache['media_by_date']?.keys.toList()
      ?..sort((a, b) => b.compareTo(a));

    if (dates == null || dates.isEmpty) return [];

    final recent_media = <Map<String, dynamic>>[];
    for (final date in dates) {
      final media = get_media_by_date(date);
      recent_media.addAll(media);
      if (recent_media.length >= limit) break;
    }

    return recent_media.take(limit).toList();
  }

  Future<void> _save_cache() async {
    // Implementation of _save_cache method
  }
}
