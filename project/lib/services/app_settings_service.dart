import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService extends ChangeNotifier {
  static const String _aiMediaContextLimitKey = 'ai_media_context_limit';
  static const String _aiMediaContextEnabledKey = 'ai_media_context_enabled';
  static const String _voiceTranscriptionTimeoutKey =
      'voice_transcription_timeout';

  // Default values
  static const int _defaultMediaContextLimit = 25;
  static const bool _defaultMediaContextEnabled = true;
  static const int _defaultVoiceTranscriptionTimeout =
      120; // 2 minutes in seconds

  bool _isInitialized = false;
  int _aiMediaContextLimit = _defaultMediaContextLimit;
  bool _aiMediaContextEnabled = _defaultMediaContextEnabled;
  int _voiceTranscriptionTimeout = _defaultVoiceTranscriptionTimeout;

  // Getters
  bool get isInitialized => _isInitialized;
  int get aiMediaContextLimit => _aiMediaContextLimit;
  bool get aiMediaContextEnabled => _aiMediaContextEnabled;
  int get voiceTranscriptionTimeout => _voiceTranscriptionTimeout;

  /// Initialize the service by loading settings from SharedPreferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load AI media context settings
      _aiMediaContextLimit =
          prefs.getInt(_aiMediaContextLimitKey) ?? _defaultMediaContextLimit;
      _aiMediaContextEnabled = prefs.getBool(_aiMediaContextEnabledKey) ??
          _defaultMediaContextEnabled;

      // Load voice transcription timeout
      _voiceTranscriptionTimeout =
          prefs.getInt(_voiceTranscriptionTimeoutKey) ??
              _defaultVoiceTranscriptionTimeout;

      // Validate the limit is within reasonable bounds
      if (_aiMediaContextLimit < 10) {
        _aiMediaContextLimit = 10;
      } else if (_aiMediaContextLimit > 500) {
        _aiMediaContextLimit = 500;
      }

      // Validate timeout is within reasonable bounds (30 seconds to 10 minutes)
      if (_voiceTranscriptionTimeout < 30) {
        _voiceTranscriptionTimeout = 30;
      } else if (_voiceTranscriptionTimeout > 600) {
        _voiceTranscriptionTimeout = 600;
      }

      _isInitialized = true;

      if (kDebugMode) {
        print('🔧 AppSettingsService initialized:');
        print('   AI Media Context Limit: $_aiMediaContextLimit');
        print('   AI Media Context Enabled: $_aiMediaContextEnabled');
        print('   Voice Transcription Timeout: $_voiceTranscriptionTimeout');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize AppSettingsService: $e');
      }

      // Use defaults on error
      _aiMediaContextLimit = _defaultMediaContextLimit;
      _aiMediaContextEnabled = _defaultMediaContextEnabled;
      _voiceTranscriptionTimeout = _defaultVoiceTranscriptionTimeout;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Update the AI media context limit
  Future<void> setAiMediaContextLimit(int limit) async {
    if (!_isInitialized) {
      throw StateError(
          'AppSettingsService not initialized. Call initialize() first.');
    }

    // Validate limit is within reasonable bounds
    if (limit < 10) {
      limit = 10;
    } else if (limit > 500) {
      limit = 500;
    }

    if (_aiMediaContextLimit == limit) return;

    _aiMediaContextLimit = limit;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_aiMediaContextLimitKey, limit);

      if (kDebugMode) {
        print('🔧 AI Media Context Limit updated to: $limit');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save AI Media Context Limit: $e');
      }
      rethrow;
    }
  }

  /// Toggle AI media context enabled/disabled
  Future<void> setAiMediaContextEnabled(bool enabled) async {
    if (!_isInitialized) {
      throw StateError(
          'AppSettingsService not initialized. Call initialize() first.');
    }

    if (_aiMediaContextEnabled == enabled) return;

    _aiMediaContextEnabled = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_aiMediaContextEnabledKey, enabled);

      if (kDebugMode) {
        print('🔧 AI Media Context ${enabled ? 'enabled' : 'disabled'}');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save AI Media Context Enabled setting: $e');
      }
      rethrow;
    }
  }

  /// Update voice transcription timeout
  Future<void> setVoiceTranscriptionTimeout(int timeout) async {
    if (!_isInitialized) {
      throw StateError(
          'AppSettingsService not initialized. Call initialize() first.');
    }

    if (_voiceTranscriptionTimeout == timeout) return;

    _voiceTranscriptionTimeout = timeout;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_voiceTranscriptionTimeoutKey, timeout);

      if (kDebugMode) {
        print('🔧 Voice Transcription Timeout updated to: $timeout');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save Voice Transcription Timeout: $e');
      }
      rethrow;
    }
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    if (!_isInitialized) {
      throw StateError(
          'AppSettingsService not initialized. Call initialize() first.');
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // Remove all settings keys
      await prefs.remove(_aiMediaContextLimitKey);
      await prefs.remove(_aiMediaContextEnabledKey);
      await prefs.remove(_voiceTranscriptionTimeoutKey);

      // Reset to defaults
      _aiMediaContextLimit = _defaultMediaContextLimit;
      _aiMediaContextEnabled = _defaultMediaContextEnabled;
      _voiceTranscriptionTimeout = _defaultVoiceTranscriptionTimeout;

      if (kDebugMode) {
        print('🔧 AppSettingsService reset to defaults');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to reset AppSettingsService: $e');
      }
      rethrow;
    }
  }

  /// Get all current settings as a map (useful for debugging or export)
  Map<String, dynamic> getAllSettings() {
    if (!_isInitialized) {
      throw StateError(
          'AppSettingsService not initialized. Call initialize() first.');
    }

    return {
      'ai_media_context_limit': _aiMediaContextLimit,
      'ai_media_context_enabled': _aiMediaContextEnabled,
      'voice_transcription_timeout': _voiceTranscriptionTimeout,
    };
  }
}
