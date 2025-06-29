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

  bool _isInitialized = false;
  bool _isCustomDirectoriesEnabled = false;
  List<MediaDirectory> _directories = [];
  MediaDirectory? _activeDirectory;

  bool get isInitialized => _isInitialized;
  bool get isCustomDirectoriesEnabled => _isCustomDirectoriesEnabled;
  List<MediaDirectory> get directories {
    if (!_isInitialized) {
      throw StateError(
          'DirectoryService not initialized. Call initialize() first.');
    }
    return List.unmodifiable(_directories);
  }

  List<MediaDirectory> get enabledDirectories =>
      _directories.where((d) => d.isEnabled).toList();
  MediaDirectory? get activeDirectory => _activeDirectory;

  /// Get platform-specific default directories
  static List<MediaDirectory> getPlatformDefaults() {
    final List<MediaDirectory> defaults = [];

    if (Platform.isAndroid) {
      defaults.add(const MediaDirectory(
        id: 'default_android_camera',
        path: '/storage/emulated/0/DCIM/Camera',
        displayName: 'Camera',
        isDefault: true,
        isEnabled: true,
      ));
      defaults.add(const MediaDirectory(
        id: 'default_android_pictures',
        path: '/storage/emulated/0/Pictures',
        displayName: 'Pictures',
        isDefault: true,
        isEnabled: true,
      ));
    } else if (Platform.isIOS) {
      defaults.add(const MediaDirectory(
        id: 'default_ios_photos',
        path: 'Photos',
        displayName: 'Camera Roll',
        isDefault: true,
        isEnabled: true,
      ));
    }

    return defaults;
  }

  /// Initialize the service with stored preferences
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isCustomDirectoriesEnabled = prefs.getBool(_enabledKey) ?? false;

      // Load saved directories
      final jsonList = prefs.getStringList(_prefsKey) ?? [];
      final savedDirectories = jsonList.map((dirString) {
        final params = Map.fromEntries(
          dirString.split('&').map((param) {
            final parts = param.split('=');
            return MapEntry(parts[0], Uri.decodeComponent(parts[1]));
          }),
        );
        return MediaDirectory(
          id: params['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
          displayName: params['displayName'] ?? '',
          path: params['path'] ?? '',
          isDefault: params['isDefault']?.toLowerCase() == 'true',
          isEnabled: params['isEnabled']?.toLowerCase() == 'true',
        );
      }).toList();

      // Merge saved directories with platform defaults
      final defaults = getPlatformDefaults();
      _directories = [...defaults];

      // Add non-default saved directories
      for (final dir in savedDirectories) {
        if (!dir.isDefault && !_directories.any((d) => d.path == dir.path)) {
          _directories.add(dir);
        }
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to load directory settings: $e');
      }
      // Use defaults
      _isCustomDirectoriesEnabled = false;
      _directories = getPlatformDefaults();
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Helper to encode values for URL storage
  String _encodeValue(String value) {
    return Uri.encodeComponent(value);
  }

  /// Toggle custom directories mode
  Future<void> setCustomDirectoriesEnabled(bool enabled) async {
    _isCustomDirectoriesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
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
      notifyListeners();
    }
  }

  /// Reset to platform defaults
  Future<void> resetToDefaults() async {
    _directories = getPlatformDefaults();
    await _saveDirectories();

    if (kDebugMode) {
      print('📁 Reset to platform defaults');
    }
    notifyListeners();
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

      // Only save non-default directories since defaults are platform-specific
      final nonDefaultDirs = _directories.where((dir) => !dir.isDefault);

      final jsonList = nonDefaultDirs.map((dir) {
        final json = dir.toJson();
        return json.entries
            .map((entry) =>
                '${entry.key}=${_encodeValue(entry.value.toString())}')
            .join('&');
      }).toList();

      await prefs.setStringList(_prefsKey, jsonList);

      if (kDebugMode) {
        print(
            '✅ Saved ${nonDefaultDirs.length} custom directories to preferences');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save directories: $e');
      }
    }
  }

  Future<void> setActiveDirectory(String path) async {
    final directory = _directories.firstWhere(
      (d) => d.path == path,
      orElse: () => MediaDirectory(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        path: path,
        displayName: path.split(Platform.pathSeparator).last,
        isDefault: false,
        isEnabled: true,
      ),
    );

    if (!_directories.contains(directory)) {
      _directories.add(directory);
      await _saveDirectories();
    }

    _activeDirectory = directory;
    notifyListeners();
  }

  Future<void> addDirectory(String path) async {
    final displayName = path.split(Platform.pathSeparator).last;
    final directory = MediaDirectory(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      path: path,
      displayName: displayName,
      isDefault: false,
      isEnabled: true,
    );

    if (!_directories.contains(directory)) {
      _directories.add(directory);
      await _saveDirectories();
      notifyListeners();
    }
  }

  Future<void> toggleDirectory(String path, bool enabled) async {
    final index = _directories.indexWhere((d) => d.path == path);
    if (index != -1) {
      final directory = _directories[index];
      _directories[index] = MediaDirectory(
        id: directory.id,
        path: directory.path,
        displayName: directory.displayName,
        isDefault: directory.isDefault,
        isEnabled: enabled,
      );
      await _saveDirectories();
      notifyListeners();
    }
  }
}
