import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionManager extends ChangeNotifier {
  bool _hasMicrophonePermission = false;
  bool _hasMediaPermission = false;
  bool _isRequestingPermissions = false;
  bool _isRequestingMicrophone = false;
  bool _isRequestingMedia = false;

  // Getters
  bool get hasMicrophonePermission => _hasMicrophonePermission;
  bool get hasMediaPermission => _hasMediaPermission;
  bool get hasAllPermissions => _hasMicrophonePermission && _hasMediaPermission;
  bool get isRequestingPermissions => _isRequestingPermissions;
  bool get isRequestingMicrophone => _isRequestingMicrophone;
  bool get isRequestingMedia => _isRequestingMedia;

  /// Request microphone permission specifically
  /// Always requests permission if not granted, regardless of previous denials
  Future<bool> requestMicrophonePermission() async {
    if (_isRequestingMicrophone) return _hasMicrophonePermission;

    _isRequestingMicrophone = true;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('🎤 Requesting microphone permission...');
      }

      // First check current status
      final currentStatus = await Permission.microphone.status;

      if (currentStatus.isGranted) {
        _hasMicrophonePermission = true;
        if (kDebugMode) {
          print('🎤 Microphone permission: ✅ Already granted');
        }
        notifyListeners();
        return true;
      }

      // If permanently denied, don't request - just return false
      if (currentStatus.isPermanentlyDenied) {
        _hasMicrophonePermission = false;
        if (kDebugMode) {
          print(
              '🎤 Microphone permission: ❌ Permanently denied - cannot request');
          print('   User must enable in device settings');
        }
        notifyListeners();
        return false;
      }

      // Permission is denied but not permanently - we can request it
      if (kDebugMode) {
        print(
            '🎤 Microphone permission denied but not permanent - requesting...');
      }

      final status = await Permission.microphone.request();
      _hasMicrophonePermission = status.isGranted;

      if (kDebugMode) {
        print(
            '🎤 Microphone permission request result: ${_hasMicrophonePermission ? '✅ Granted' : '❌ Denied'}');
        if (!_hasMicrophonePermission) {
          print('   Status: ${status.name}');
          if (status.isPermanentlyDenied) {
            print('   ⚠️ Now permanently denied - user needs device settings');
          } else {
            print('   ⚠️ Denied but can retry on next attempt');
          }
        }
      }

      notifyListeners();
      return _hasMicrophonePermission;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error requesting microphone permission: $e');
      }
      _hasMicrophonePermission = false;
      notifyListeners();
      return false;
    } finally {
      _isRequestingMicrophone = false;
      notifyListeners();
    }
  }

  /// Request media permission specifically
  /// Always requests permission if not granted, regardless of previous denials
  Future<bool> requestMediaPermission() async {
    if (_isRequestingMedia) return _hasMediaPermission;

    _isRequestingMedia = true;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('📱 Requesting media permission...');
      }

      // First check current status
      final currentState = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );

      if (currentState.hasAccess) {
        _hasMediaPermission = true;
        if (kDebugMode) {
          print('📱 Media permission: ✅ Already granted');
        }
        notifyListeners();
        return true;
      }

      // If restricted (permanently denied), don't request - just return false
      if (currentState == PermissionState.restricted) {
        _hasMediaPermission = false;
        if (kDebugMode) {
          print(
              '📱 Media permission: ❌ Restricted/permanently denied - cannot request');
          print('   User must enable in device settings');
        }
        notifyListeners();
        return false;
      }

      // Permission is denied but not permanently - we can request it
      if (kDebugMode) {
        print('📱 Media permission denied but not permanent - requesting...');
      }

      final permissionState = await PhotoManager.requestPermissionExtend();
      _hasMediaPermission = permissionState.hasAccess;

      if (kDebugMode) {
        print(
            '📱 Media permission request result: ${_hasMediaPermission ? '✅ Granted' : '❌ Denied'}');
        if (!_hasMediaPermission) {
          print('   State: ${permissionState.name}');
          if (permissionState == PermissionState.restricted) {
            print('   ⚠️ Now restricted - user needs device settings');
          } else if (permissionState == PermissionState.denied) {
            print('   ⚠️ Denied but can retry on next attempt');
          }
        }
      }

      notifyListeners();
      return _hasMediaPermission;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error requesting media permission: $e');
      }
      _hasMediaPermission = false;
      notifyListeners();
      return false;
    } finally {
      _isRequestingMedia = false;
      notifyListeners();
    }
  }

  /// Check if microphone permission is permanently denied
  Future<bool> isMicrophonePermissionPermanentlyDenied() async {
    try {
      final status = await Permission.microphone.status;
      return status.isPermanentlyDenied;
    } catch (e) {
      return false;
    }
  }

  /// Check if media permission is permanently denied
  Future<bool> isMediaPermissionPermanentlyDenied() async {
    try {
      final permissionState = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      return permissionState == PermissionState.restricted;
    } catch (e) {
      return false;
    }
  }

  /// Open device settings for the user to manually enable permissions
  Future<bool> openDeviceSettings() async {
    try {
      if (kDebugMode) {
        print('🔧 Opening app settings for manual permission configuration...');
      }

      final opened = await openAppSettings();

      if (kDebugMode) {
        print('🔧 App settings opened: ${opened ? '✅ Success' : '❌ Failed'}');
      }

      return opened;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error opening app settings: $e');
      }
      return false;
    }
  }

  /// Get a user-friendly message for permission status
  String getPermissionStatusMessage({
    required bool isMicrophoneRequired,
    required bool isMediaRequired,
  }) {
    final List<String> missingPermissions = [];

    if (isMicrophoneRequired && !_hasMicrophonePermission) {
      missingPermissions.add('Microphone');
    }

    if (isMediaRequired && !_hasMediaPermission) {
      missingPermissions.add('Media access');
    }

    if (missingPermissions.isEmpty) {
      return 'All required permissions are granted';
    }

    if (missingPermissions.length == 1) {
      return '${missingPermissions.first} permission is required';
    }

    return '${missingPermissions.join(' and ')} permissions are required';
  }

  /// Request all required permissions at once
  /// This method now uses the individual permission request methods
  Future<bool> requestAllPermissions() async {
    if (_isRequestingPermissions) return hasAllPermissions;
    _isRequestingPermissions = true;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('🔐 Requesting all required permissions...');
      }

      // Request both permissions
      final microphoneGranted = await requestMicrophonePermission();
      final mediaGranted = await requestMediaPermission();

      final allGranted = microphoneGranted && mediaGranted;

      if (kDebugMode) {
        print(
            '🔐 All permissions result: ${allGranted ? '✅ All granted' : '❌ Some denied'}');
        print('   Media: ${mediaGranted ? '✅' : '❌'}');
        print('   Microphone: ${microphoneGranted ? '✅' : '❌'}');
      }

      return allGranted;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error requesting all permissions: $e');
      }
      return false;
    } finally {
      _isRequestingPermissions = false;
      notifyListeners();
    }
  }

  /// Check current permission status without requesting
  Future<void> checkPermissions() async {
    try {
      // Check media permissions without requesting
      final mediaPermissionState = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      _hasMediaPermission = mediaPermissionState.hasAccess;

      // Check microphone permission without requesting
      _hasMicrophonePermission = await Permission.microphone.status.isGranted;

      if (kDebugMode) {
        print('📋 Permission check (no request):');
        print('   Media: ${_hasMediaPermission ? '✅' : '❌'}');
        print('   Microphone: ${_hasMicrophonePermission ? '✅' : '❌'}');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking permissions: $e');
      }
    }
  }

  /// Reset permission states (for testing or state management)
  void resetPermissionStates() {
    _hasMicrophonePermission = false;
    _hasMediaPermission = false;
    _isRequestingPermissions = false;
    _isRequestingMicrophone = false;
    _isRequestingMedia = false;
    notifyListeners();

    if (kDebugMode) {
      print('🔄 Permission states reset');
    }
  }
}
