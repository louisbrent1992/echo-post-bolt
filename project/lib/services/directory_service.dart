import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class MediaDirectory {
  final String id;
  final String displayName;
  final String path;
  final bool isDefault;
  final bool isEnabled;

  const MediaDirectory({
    required this.id,
    required this.displayName,
    required this.path,
    required this.isDefault,
    required this.isEnabled,
  });

  factory MediaDirectory.fromJson(Map<String, dynamic> json) {
    return MediaDirectory(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      path: json['path'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'path': path,
      'isDefault': isDefault,
      'isEnabled': isEnabled,
    };
  }

  MediaDirectory copyWith({
    String? id,
    String? displayName,
    String? path,
    bool? isDefault,
    bool? isEnabled,
  }) {
    return MediaDirectory(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      path: path ?? this.path,
      isDefault: isDefault ?? this.isDefault,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class DirectoryService extends ChangeNotifier {
  static const String _prefsKey = 'media_directories';
  static const String _enabledKey = 'custom_directories_enabled';

  List<MediaDirectory> _directories = [];
  bool _isInitialized = false;
  bool _customDirectoriesEnabled = false;

  /// Get platform-specific default directories
  static List<MediaDirectory> getPlatformDefaults() {
    if (Platform.isAndroid) {
      return [
        const MediaDirectory(
          id: 'android_dcim_camera',
          displayName: 'Camera Photos',
          path: '/storage/emulated/0/DCIM/Camera',
          isDefault: true,
          isEnabled: true,
        ),
        const MediaDirectory(
          id: 'android_pictures',
          displayName: 'Pictures',
          path: '/storage/emulated/0/Pictures',
          isDefault: true,
          isEnabled: true,
        ),
        const MediaDirectory(
          id: 'android_downloads',
          displayName: 'Downloads',
          path: '/storage/emulated/0/Download',
          isDefault: true,
          isEnabled: false,
        ),
        const MediaDirectory(
          id: 'android_whatsapp_images',
          displayName: 'WhatsApp Images',
          path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
          isDefault: false,
          isEnabled: false,
        ),
        const MediaDirectory(
          id: 'android_screenshots',
          displayName: 'Screenshots',
          path: '/storage/emulated/0/Pictures/Screenshots',
          isDefault: false,
          isEnabled: false,
        ),
      ];
    } else if (Platform.isIOS) {
      return [
        const MediaDirectory(
          id: 'ios_photos',
          displayName: 'Photos Library',
          path: 'NSDocumentDirectory/Photos',
          isDefault: true,
          isEnabled: true,
        ),
        const MediaDirectory(
          id: 'ios_documents',
          displayName: 'Documents',
          path: 'NSDocumentDirectory',
          isDefault: true,
          isEnabled: false,
        ),
        const MediaDirectory(
          id: 'ios_downloads',
          displayName: 'Downloads',
          path: 'NSDownloadsDirectory',
          isDefault: false,
          isEnabled: false,
        ),
      ];
    } else {
      // Desktop fallbacks
      return [
        const MediaDirectory(
          id: 'default_pictures',
          displayName: 'Pictures',
          path: 'Pictures',
          isDefault: true,
          isEnabled: true,
        ),
        const MediaDirectory(
          id: 'default_downloads',
          displayName: 'Downloads',
          path: 'Downloads',
          isDefault: false,
          isEnabled: false,
        ),
      ];
    }
  }

  /// Initialize the service with stored preferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load custom directories enabled flag
      _customDirectoriesEnabled = prefs.getBool(_enabledKey) ?? false;

      // Load stored directories or use defaults
      final stored = prefs.getStringList(_prefsKey);
      if (stored != null && stored.isNotEmpty) {
        _directories = stored
            .map((jsonStr) {
              try {
                final Map<String, dynamic> json = Map<String, dynamic>.from(
                    Uri.splitQueryString(jsonStr)
                        .map((k, v) => MapEntry(k, _decodeValue(v))));
                return MediaDirectory.fromJson(json);
              } catch (e) {
                if (kDebugMode) {
                  print('Error parsing stored directory: $e');
                }
                return null;
              }
            })
            .where((dir) => dir != null)
            .cast<MediaDirectory>()
            .toList();
      }

      // If no stored directories, use platform defaults
      if (_directories.isEmpty) {
        _directories = getPlatformDefaults();
        await _saveDirectories();
      }

      _isInitialized = true;

      if (kDebugMode) {
        print('📁 DirectoryService initialized');
        print('   Custom directories enabled: $_customDirectoriesEnabled');
        print('   Total directories: ${_directories.length}');
        for (final dir in _directories) {
          print(
              '   - ${dir.displayName} (${dir.path}) - enabled: ${dir.isEnabled}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize DirectoryService: $e');
      }
      // Fallback to platform defaults
      _directories = getPlatformDefaults();
      _isInitialized = true;
    }
  }

  /// Helper to decode URL-encoded values
  String _decodeValue(String value) {
    return Uri.decodeComponent(value);
  }

  /// Helper to encode values for URL storage
  String _encodeValue(String value) {
    return Uri.encodeComponent(value);
  }

  /// Get all directories
  List<MediaDirectory> get directories {
    if (!_isInitialized) {
      throw StateError(
          'DirectoryService not initialized. Call initialize() first.');
    }
    return List.unmodifiable(_directories);
  }

  /// Get enabled directories only
  List<MediaDirectory> get enabledDirectories {
    return directories.where((dir) => dir.isEnabled).toList();
  }

  /// Check if custom directories are enabled (vs album-only mode)
  bool get isCustomDirectoriesEnabled => _customDirectoriesEnabled;

  /// Toggle custom directories mode
  Future<void> setCustomDirectoriesEnabled(bool enabled) async {
    _customDirectoriesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);

    if (kDebugMode) {
      print('📁 Custom directories ${enabled ? 'enabled' : 'disabled'}');
    }
  }

  /// Update a directory's enabled status
  Future<void> updateDirectoryEnabled(String directoryId, bool enabled) async {
    final index = _directories.indexWhere((dir) => dir.id == directoryId);
    if (index != -1) {
      _directories[index] = _directories[index].copyWith(isEnabled: enabled);
      await _saveDirectories();

      if (kDebugMode) {
        print(
            '📁 Directory ${_directories[index].displayName} ${enabled ? 'enabled' : 'disabled'}');
      }
    }
  }

  /// Add a custom directory
  Future<void> addCustomDirectory(String displayName, String path) async {
    // Check if directory already exists
    final exists = _directories.any((dir) => dir.path == path);
    if (exists) {
      throw Exception('Directory already exists: $path');
    }

    // Verify path exists (for platform directories)
    if (Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        throw Exception('Directory does not exist: $path');
      }
    }

    final newDirectory = MediaDirectory(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      displayName: displayName,
      path: path,
      isDefault: false,
      isEnabled: true,
    );

    _directories.add(newDirectory);
    await _saveDirectories();

    if (kDebugMode) {
      print('📁 Added custom directory: $displayName ($path)');
    }
  }

  /// Remove a custom directory (can't remove defaults)
  Future<void> removeDirectory(String directoryId) async {
    final index = _directories.indexWhere((dir) => dir.id == directoryId);
    if (index != -1) {
      final directory = _directories[index];
      if (directory.isDefault) {
        throw Exception('Cannot remove default directory');
      }

      _directories.removeAt(index);
      await _saveDirectories();

      if (kDebugMode) {
        print('📁 Removed directory: ${directory.displayName}');
      }
    }
  }

  /// Reset to platform defaults
  Future<void> resetToDefaults() async {
    _directories = getPlatformDefaults();
    await _saveDirectories();

    if (kDebugMode) {
      print('📁 Reset to platform defaults');
    }
  }

  /// Check if a directory path exists and is accessible
  Future<bool> isDirectoryAccessible(String path) async {
    try {
      if (Platform.isIOS) {
        // On iOS, we can't directly check file system paths
        // This would need to be handled through the Photos framework
        return true; // Assume accessible for iOS
      }

      final dir = Directory(path);
      return await dir.exists();
    } catch (e) {
      if (kDebugMode) {
        print('Error checking directory accessibility: $e');
      }
      return false;
    }
  }

  /// Get suggested directories based on common patterns
  Future<List<String>> getSuggestedDirectories() async {
    if (Platform.isAndroid) {
      final suggestions = <String>[
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
        '/storage/emulated/0/Pictures/Screenshots',
        '/storage/emulated/0/Pictures/Instagram',
        '/storage/emulated/0/Pictures/Facebook',
      ];

      // Filter to only existing directories
      final existing = <String>[];
      for (final suggestion in suggestions) {
        if (await isDirectoryAccessible(suggestion)) {
          existing.add(suggestion);
        }
      }
      return existing;
    } else if (Platform.isIOS) {
      // iOS has restricted file system access
      return [
        'NSDocumentDirectory/Photos',
        'NSDocumentDirectory',
        'NSDownloadsDirectory',
      ];
    } else {
      // Desktop platforms
      return [
        path.join(Platform.environment['HOME'] ?? '', 'Pictures'),
        path.join(Platform.environment['HOME'] ?? '', 'Downloads'),
        path.join(Platform.environment['HOME'] ?? '', 'Documents'),
      ];
    }
  }

  /// Save directories to persistent storage
  Future<void> _saveDirectories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _directories.map((dir) {
        final json = dir.toJson();
        return json.entries
            .map((entry) =>
                '${entry.key}=${_encodeValue(entry.value.toString())}')
            .join('&');
      }).toList();

      await prefs.setStringList(_prefsKey, jsonList);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save directories: $e');
      }
    }
  }
}
