import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for loading environment variables from JSON files
class JsonEnvService {
  static Map<String, dynamic>? _envData;
  static bool _isInitialized = false;

  /// Initialize the environment service by loading the JSON file
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) {
        // For web, we need to load the file differently
        await _loadForWeb();
      } else {
        // For mobile, load from file system
        await _loadForMobile();
      }
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to load environment from JSON: $e');
      }
      // Fallback to empty map
      _envData = {};
    }
  }

  /// Load environment for web platform
  static Future<void> _loadForWeb() async {
    try {
      // Try to load from assets first
      final jsonString = await rootBundle.loadString('assets/.env_local.json');
      _envData = json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ Could not load .env_local.json from assets, trying alternative methods...');
      }

      // For web builds, we might need to include the file in the build
      // or use a different approach
      _envData = _getDefaultEnvData();
    }
  }

  /// Load environment for mobile platform
  static Future<void> _loadForMobile() async {
    try {
      final file = File('.env_local.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        _envData = json.decode(jsonString) as Map<String, dynamic>;
      } else {
        if (kDebugMode) {
          print('⚠️ .env_local.json not found, using default values');
        }
        _envData = _getDefaultEnvData();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error reading .env_local.json: $e');
      }
      _envData = _getDefaultEnvData();
    }
  }

  /// Get default environment data (fallback)
  static Map<String, dynamic> _getDefaultEnvData() {
    return {
      'BACKEND_URL': 'http://localhost:3000',
      'ENVIRONMENT': 'development',
      'DEBUG_MODE': 'true',
    };
  }

  /// Get an environment variable
  static String? get(String key) {
    if (!_isInitialized) {
      if (kDebugMode) {
        print('⚠️ JsonEnvService not initialized. Call initialize() first.');
      }
      return null;
    }

    return _envData?[key]?.toString();
  }

  /// Get an environment variable with a default value
  static String getOrDefault(String key, String defaultValue) {
    return get(key) ?? defaultValue;
  }

  /// Get a boolean environment variable
  static bool getBool(String key, {bool defaultValue = false}) {
    final value = get(key);
    if (value == null) return defaultValue;

    return value.toLowerCase() == 'true';
  }

  /// Get an integer environment variable
  static int? getInt(String key) {
    final value = get(key);
    if (value == null) return null;

    return int.tryParse(value);
  }

  /// Get an integer environment variable with a default value
  static int getIntOrDefault(String key, int defaultValue) {
    return getInt(key) ?? defaultValue;
  }

  /// Check if an environment variable exists
  static bool has(String key) {
    return _envData?.containsKey(key) ?? false;
  }

  /// Get all environment variables
  static Map<String, dynamic> getAll() {
    return Map.from(_envData ?? {});
  }

  /// Get environment variables for a specific platform
  static Map<String, String> getPlatformVars(String platform) {
    final vars = <String, String>{};
    final prefix = platform.toUpperCase();

    _envData?.forEach((key, value) {
      if (key.startsWith(prefix)) {
        vars[key] = value.toString();
      }
    });

    return vars;
  }

  /// Get OAuth configuration for a specific platform
  static Map<String, String> getOAuthConfig(String platform) {
    final config = <String, String>{};
    final platformUpper = platform.toUpperCase();

    // Common OAuth keys
    final keys = [
      'CLIENT_ID',
      'CLIENT_SECRET',
      'APP_ID',
      'APP_SECRET',
      'API_KEY',
      'REDIRECT_URI'
    ];

    for (final key in keys) {
      final fullKey = '${platformUpper}_$key';
      final value = get(fullKey);
      if (value != null) {
        config[key] = value;
      }
    }

    return config;
  }

  /// Validate required environment variables
  static List<String> validateRequiredVars(List<String> requiredVars) {
    final missing = <String>[];

    for (final varName in requiredVars) {
      if (!has(varName) || get(varName)?.isEmpty == true) {
        missing.add(varName);
      }
    }

    return missing;
  }

  /// Get environment status summary
  static Map<String, dynamic> getEnvironmentStatus() {
    final status = <String, dynamic>{
      'isInitialized': _isInitialized,
      'totalVars': _envData?.length ?? 0,
      'environment': get('ENVIRONMENT') ?? 'unknown',
      'debugMode': getBool('DEBUG_MODE'),
      'platforms': <String, Map<String, dynamic>>{},
    };

    // Check platform configurations
    final platforms = ['twitter', 'tiktok', 'facebook', 'instagram', 'youtube'];
    for (final platform in platforms) {
      final config = getOAuthConfig(platform);
      status['platforms'][platform] = {
        'configured': config.isNotEmpty,
        'vars': config.keys.toList(),
      };
    }

    return status;
  }

  /// Reload environment data
  static Future<void> reload() async {
    _isInitialized = false;
    _envData = null;
    await initialize();
  }
}
